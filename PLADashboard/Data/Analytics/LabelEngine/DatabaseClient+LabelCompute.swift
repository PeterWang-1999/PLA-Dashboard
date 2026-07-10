import Foundation
import GRDB

enum LabelRecomputeOutcome: Sendable, Equatable {
    case skippedNoAdsData
    case skippedInsufficientWeeks(available: Int)
    case skippedAlreadyComputed(weekId: String)
    case computed(weekId: String, productCount: Int, historyNote: String)
}

extension DatabaseClient {
    static let labelSnapshotRetentionCount = 26

    /// 自建站标签重算。
    /// - Parameters:
    ///   - force: 清空历史后仅入池。
    ///   - refreshSameWeek: 允许覆盖本周已有快照（毛利晚于投放导入、同周重导时使用）。
    @discardableResult
    func recomputeWarningLabelsIfNeeded(
        force: Bool = false,
        refreshSameWeek: Bool = false
    ) throws -> LabelRecomputeOutcome {
        let signpost = PerformanceSignposts.beginETLRebuild()
        defer { PerformanceSignposts.endETLRebuild(signpost) }

        guard let latestDay = try fetchLatestMetricDay(),
              let latestDate = WeekCalendar.parseDay(latestDay) else {
            return .skippedNoAdsData
        }

        let weekStarts = WeekCalendar.reportingWeekStarts(endingAt: latestDate)
        guard weekStarts.count == LabelEngineConstants.reportingWeekCount,
              let currentWeek = weekStarts.last else {
            return .skippedInsufficientWeeks(available: weekStarts.count)
        }

        if !force, let latestWeekId = try latestLabelSnapshotWeekId() {
            if latestWeekId > currentWeek {
                return .skippedAlreadyComputed(weekId: latestWeekId)
            }
            if latestWeekId == currentWeek, !refreshSameWeek {
                return .skippedAlreadyComputed(weekId: latestWeekId)
            }
        }

        var previousProducts: [String: LabelSnapshotProductState] = [:]
        var historyNote = "无历史快照，本周仅按入池规则初始化"

        if force {
            try resetLabelHistory()
            historyNote = "已重置历史，本周仅按入池规则初始化"
        } else if let latestWeekId = try latestLabelSnapshotWeekId() {
            if latestWeekId == currentWeek {
                if let earlier = try labelSnapshotWeekId(before: currentWeek) {
                    previousProducts = try loadLabelSnapshotProductStates(weekId: earlier)
                    historyNote = "重跑本周 \(currentWeek)，以上周快照 \(earlier) 做留池/出池"
                } else {
                    historyNote = "重跑本周 \(currentWeek)，无更早快照，按入池初始化"
                }
            } else if latestWeekId < currentWeek {
                previousProducts = try loadLabelSnapshotProductStates(weekId: latestWeekId)
                historyNote = "读取上周快照 \(latestWeekId)，执行留池/出池复查"
            }
        }

        let metrics = try buildLabelMetrics(weekStarts: weekStarts)
        let machine = LabelStateMachine.apply(
            metrics: metrics,
            previousProducts: previousProducts,
            historyNote: historyNote
        )
        try persistLabelSnapshot(
            weekId: currentWeek,
            weekStarts: weekStarts,
            historyNote: machine.historyNote,
            decisions: machine.decisions
        )

        return .computed(
            weekId: currentWeek,
            productCount: machine.decisions.count,
            historyNote: machine.historyNote
        )
    }

    func resetLabelHistory() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM label_snapshot_products;")
            try db.execute(sql: "DELETE FROM label_snapshots;")
        }
        invalidateDashboardCache()
    }

    func latestLabelSnapshotWeekId() throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT week_id FROM label_snapshots ORDER BY week_id DESC LIMIT 1;"
            )
        }
    }

    func labelSnapshotWeekId(before weekId: String) throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(
                db,
                sql: """
                    SELECT week_id FROM label_snapshots
                    WHERE week_id < ?
                    ORDER BY week_id DESC
                    LIMIT 1;
                    """,
                arguments: [weekId]
            )
        }
    }

    func loadLabelSnapshotProductStates(weekId: String) throws -> [String: LabelSnapshotProductState] {
        try dbQueue.read { db in
            let rows = try LabelSnapshotProductRecord
                .filter(LabelSnapshotProductRecord.Columns.weekId == weekId)
                .fetchAll(db)
            var map: [String: LabelSnapshotProductState] = [:]
            map.reserveCapacity(rows.count)
            for row in rows {
                map[row.productId] = row.asPreviousState
            }
            return map
        }
    }

    /// 最新一周快照的产品标签（看板 Phase 3 读取）。
    func loadLatestLabelDecisionsByProductId() throws -> [String: String] {
        guard let weekId = try latestLabelSnapshotWeekId() else { return [:] }
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT product_id, label
                    FROM label_snapshot_products
                    WHERE week_id = ?;
                    """,
                arguments: [weekId]
            )
            var map: [String: String] = [:]
            map.reserveCapacity(rows.count)
            for row in rows {
                if let id: String = row["product_id"], let label: String = row["label"] {
                    map[id] = label
                }
            }
            return map
        }
    }

    func persistLabelSnapshot(
        weekId: String,
        weekStarts: [String],
        historyNote: String,
        decisions: [LabelProductDecision]
    ) throws {
        let createdAt = ISO8601DateFormatter().string(from: Date())
        let weeksJSON = try Self.encodeAdsWeeksJSON(weekStarts)

        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM label_snapshot_products WHERE week_id = ?;",
                arguments: [weekId]
            )
            try db.execute(
                sql: "DELETE FROM label_snapshots WHERE week_id = ?;",
                arguments: [weekId]
            )

            try LabelSnapshotRecord(
                weekId: weekId,
                createdAt: createdAt,
                adsWeeksJSON: weeksJSON,
                historyNote: historyNote
            ).insert(db)

            var productRecords: [LabelSnapshotProductRecord] = []
            productRecords.reserveCapacity(decisions.count)
            for decision in decisions {
                productRecords.append(LabelSnapshotProductRecord(
                    weekId: weekId,
                    productId: decision.productId,
                    label: decision.suggestedLabel,
                    failHighRetain: decision.failHighRetain,
                    marginLt1: decision.marginLt1,
                    noSignalRecent3: decision.noSignalRecent3,
                    noConvGSCurrentWeek: decision.noConvGSCurrentWeek,
                    roiGe1x: decision.roiGe1x,
                    marginGe1: decision.marginGe1,
                    weeksInLowSampleOld: decision.weeksInLowSampleOld,
                    weeksInPotentialNew: decision.weeksInPotentialNew,
                    transitionAction: decision.transitionAction,
                    reason: decision.reason
                ))
            }
            if !productRecords.isEmpty {
                try db.insertRecords(productRecords)
            }

            let weekIDs = try String.fetchAll(
                db,
                sql: "SELECT week_id FROM label_snapshots ORDER BY week_id ASC;"
            )
            if weekIDs.count > Self.labelSnapshotRetentionCount {
                let overflow = weekIDs.count - Self.labelSnapshotRetentionCount
                for oldWeek in weekIDs.prefix(overflow) {
                    try db.execute(
                        sql: "DELETE FROM label_snapshot_products WHERE week_id = ?;",
                        arguments: [oldWeek]
                    )
                    try db.execute(
                        sql: "DELETE FROM label_snapshots WHERE week_id = ?;",
                        arguments: [oldWeek]
                    )
                }
            }
        }
        invalidateDashboardCache()
    }

    private static func encodeAdsWeeksJSON(_ weekStarts: [String]) throws -> String {
        let data = try JSONEncoder().encode(weekStarts)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
