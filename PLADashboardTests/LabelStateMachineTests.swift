import XCTest
@testable import PLADashboard

final class LabelStateMachineTests: XCTestCase {
    private let weekStarts = [
        "2026-05-24", "2026-05-31", "2026-06-07",
        "2026-06-14", "2026-06-21", "2026-06-28",
    ]

    private var thresholds: LabelMetricsThresholds {
        LabelMetricsThresholds(
            highMarginThreshold: 1.0,
            matureMarginP50: 1.0,
            matureSampleN: 1,
            newGSP50Cents: 3_000,
            newGSP75Cents: 8_000,
            newPositiveN: 1,
            oldGSP50Cents: 4_000,
            oldPositiveN: 1,
            newCutoffDay: "2026-04-04",
            siteBenchmarkROI: 1.0
        )
    }

    func testEnterHighFromObservation() {
        let row = makeRow(
            clicks: 400,
            roi: 1.5,
            margin: 1.2,
            active3: 2,
            conversions: 5,
            isNew: false
        )
        let decision = apply(row: row, prev: .observationDefault)
        XCTAssertEqual(decision.suggestedLabel, LabelEngineConstants.labelHigh)
        XCTAssertEqual(decision.transitionAction, "新入高效")
    }

    func testPotentialHoldWhenRetainFails() {
        let row = makeRow(
            clicks: 80,
            roi: 0.5,
            margin: 1.2,
            active3: 1,
            conversions: 2,
            wgs: 1_000,
            isNew: true,
            noConvGSCurrent: false
        )
        var prev = LabelSnapshotProductState.observationDefault
        prev.label = LabelEngineConstants.labelPotential
        prev.weeksInPotentialNew = 2
        let decision = apply(row: row, prev: prev)
        XCTAssertEqual(decision.suggestedLabel, LabelEngineConstants.labelPotential)
        XCTAssertTrue(decision.transitionAction.contains("暂留"))
        XCTAssertEqual(decision.weeksInPotentialNew, 3)
    }

    func testPotentialExitAfterTwoNoSignalWeeks() {
        let row = makeRow(
            clicks: 80,
            roi: 2.0,
            margin: 1.2,
            active3: 0,
            conversions: 2,
            wgs: 10_000,
            isNew: true,
            noConvGSCurrent: true
        )
        var prev = LabelSnapshotProductState.observationDefault
        prev.label = LabelEngineConstants.labelPotential
        prev.noConvGSCurrentWeek = true
        prev.weeksInPotentialNew = 3
        let decision = apply(row: row, prev: prev)
        XCTAssertEqual(decision.suggestedLabel, LabelEngineConstants.labelObservation)
        XCTAssertTrue(decision.transitionAction.contains("出池"))
    }

    func testPotentialFirstNoSignalWeekHolds() {
        let row = makeRow(
            clicks: 80,
            roi: 0.5,
            margin: 1.2,
            active3: 1,
            conversions: 0,
            wgs: 1_000,
            isNew: true,
            noConvGSCurrent: true
        )
        var prev = LabelSnapshotProductState.observationDefault
        prev.label = LabelEngineConstants.labelPotential
        prev.noConvGSCurrentWeek = false
        prev.weeksInPotentialNew = 2
        let decision = apply(row: row, prev: prev)
        XCTAssertEqual(decision.suggestedLabel, LabelEngineConstants.labelPotential)
    }

    func testHighExitsImmediatelyOnRecent3NoSignal() {
        let row = makeRow(
            clicks: 400,
            roi: 2.0,
            margin: 1.5,
            active3: 0,
            conversions: 5,
            isNew: false,
            noConvGSCurrent: true
        )
        var prev = LabelSnapshotProductState.observationDefault
        prev.label = LabelEngineConstants.labelHigh
        let decision = apply(row: row, prev: prev)
        XCTAssertEqual(decision.suggestedLabel, LabelEngineConstants.labelObservation)
        XCTAssertTrue(decision.transitionAction.contains("高效出池"))
        XCTAssertTrue(decision.reason.contains("近3周无广告转化且无Gross Sales"))
    }

    func testOldExitsOnMarginLt1Twice() {
        let row = makeRow(
            clicks: 80,
            roi: 2.0,
            margin: 0.5,
            active3: 1,
            conversions: 2,
            wgs: 10_000,
            isNew: false,
            noConvGSCurrent: false
        )
        var prev = LabelSnapshotProductState.observationDefault
        prev.label = LabelEngineConstants.labelOld
        prev.marginLt1 = true
        prev.weeksInLowSampleOld = 2
        let decision = apply(row: row, prev: prev)
        XCTAssertEqual(decision.suggestedLabel, LabelEngineConstants.labelObservation)
    }

    func testLowExitsAfterTwoROIRecoveries() {
        let row = makeRow(
            clicks: 400,
            roi: 1.1,
            margin: 0.5,
            active3: 1,
            conversions: 5,
            isNew: false
        )
        var prev = LabelSnapshotProductState.observationDefault
        prev.label = LabelEngineConstants.labelLow
        prev.roiGe1x = true
        let decision = apply(row: row, prev: prev)
        XCTAssertEqual(decision.suggestedLabel, LabelEngineConstants.labelObservation)
        XCTAssertTrue(decision.reason.contains("连续2次广告ROI"))
    }

    func testPotentialEnterRequiresROIWhenGSP75Missing() {
        let thresholds = LabelMetricsThresholds(
            highMarginThreshold: 1.0,
            matureMarginP50: 1.0,
            matureSampleN: 1,
            newGSP50Cents: nil,
            newGSP75Cents: nil,
            newPositiveN: 0,
            oldGSP50Cents: nil,
            oldPositiveN: 0,
            newCutoffDay: "2026-04-04",
            siteBenchmarkROI: 1.0
        )

        let failRow = makeRow(
            clicks: 50,
            roi: 1.0,
            margin: 1.2,
            active3: 1,
            conversions: 1,
            wgs: 99_999,
            isNew: true
        )
        let fail = apply(row: failRow, prev: .observationDefault, thresholds: thresholds)
        XCTAssertEqual(fail.suggestedLabel, LabelEngineConstants.labelObservation)

        let okRow = makeRow(
            clicks: 50,
            roi: 1.6,
            margin: 1.2,
            active3: 1,
            conversions: 1,
            wgs: 1,
            isNew: true
        )
        let ok = apply(row: okRow, prev: .observationDefault, thresholds: thresholds)
        XCTAssertEqual(ok.suggestedLabel, LabelEngineConstants.labelPotential)
    }

    func testPrevWithoutNoConvFlagDoesNotCountAsSecondNoSignal() {
        // 对标 Python：仅有 no_signal_recent3 不得当作连续「本周无信号」
        let row = makeRow(
            clicks: 80,
            roi: 2.0,
            margin: 1.2,
            active3: 0,
            conversions: 2,
            wgs: 10_000,
            isNew: true,
            noConvGSCurrent: true
        )
        var prev = LabelSnapshotProductState.observationDefault
        prev.label = LabelEngineConstants.labelPotential
        prev.noConvGSCurrentWeek = false
        prev.weeksInPotentialNew = 3
        let decision = apply(row: row, prev: prev)
        XCTAssertEqual(decision.suggestedLabel, LabelEngineConstants.labelPotential)
    }

    func testHighFirstFailRetainHolds() {
        let row = makeRow(
            clicks: 400,
            roi: 0.5,
            margin: 1.2,
            active3: 1,
            conversions: 5,
            isNew: false
        )
        var prev = LabelSnapshotProductState.observationDefault
        prev.label = LabelEngineConstants.labelHigh
        prev.failHighRetain = false
        let decision = apply(row: row, prev: prev)
        XCTAssertEqual(decision.suggestedLabel, LabelEngineConstants.labelHigh)
        XCTAssertTrue(decision.transitionAction.contains("暂留"))
        XCTAssertTrue(decision.failHighRetain)
    }

    func testPotentialPromotesToHighAt300Clicks() {
        let row = makeRow(
            clicks: 400,
            roi: 1.5,
            margin: 1.2,
            active3: 2,
            conversions: 5,
            isNew: true
        )
        var prev = LabelSnapshotProductState.observationDefault
        prev.label = LabelEngineConstants.labelPotential
        let decision = apply(row: row, prev: prev)
        XCTAssertEqual(decision.suggestedLabel, LabelEngineConstants.labelHigh)
        XCTAssertTrue(decision.transitionAction.contains("晋升高效"))
    }

    func testEnterOldFromObservation() {
        let row = makeRow(
            clicks: 80,
            roi: 1.3,
            margin: 1.1,
            active3: 1,
            conversions: 2,
            wgs: 5_000,
            isNew: false
        )
        let decision = apply(row: row, prev: .observationDefault)
        XCTAssertEqual(decision.suggestedLabel, LabelEngineConstants.labelOld)
        XCTAssertEqual(decision.transitionAction, "新入低样本老品")
    }

    func testRerunSameWeekUsesEarlierSnapshotForRetain() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting()
        try await seedSixWeeksAds(client: client, productId: "1001")

        // 先写入「上周」高效快照，再写入本周空快照，force 重算应读上周
        let earlierWeek = "2026-06-21"
        let currentWeek = "2026-06-28"
        try await client.persistLabelSnapshot(
            weekId: earlierWeek,
            weekStarts: weekStarts,
            historyNote: "earlier",
            decisions: [
                LabelProductDecision(
                    productId: "1001",
                    previousLabel: LabelEngineConstants.labelObservation,
                    suggestedLabel: LabelEngineConstants.labelHigh,
                    transitionAction: "新入高效",
                    reason: "seed",
                    failHighRetain: false,
                    marginLt1: false,
                    noSignalRecent3: false,
                    noConvGSCurrentWeek: false,
                    roiGe1x: true,
                    marginGe1: true,
                    weeksInLowSampleOld: 0,
                    weeksInPotentialNew: 0
                ),
            ]
        )
        try await client.persistLabelSnapshot(
            weekId: currentWeek,
            weekStarts: weekStarts,
            historyNote: "current empty",
            decisions: []
        )

        // force=false 且已有本周快照会跳过；用内部路径验证 earlier 可读
        let prev = try await client.loadLabelSnapshotProductStates(weekId: earlierWeek)
        XCTAssertEqual(prev["1001"]?.label, LabelEngineConstants.labelHigh)

        let earlierId = try await client.labelSnapshotWeekId(before: currentWeek)
        XCTAssertEqual(earlierId, earlierWeek)
    }

    func testRecomputePersistsSnapshotAndSkipsSameWeek() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting()
        try await seedSixWeeksAds(client: client, productId: "1001")

        let first = try await client.recomputeWarningLabelsIfNeeded(force: false)
        guard case .computed(let weekId, let count, _) = first else {
            return XCTFail("Expected computed, got \(first)")
        }
        XCTAssertEqual(weekId, "2026-06-28")
        XCTAssertEqual(count, 1)

        let second = try await client.recomputeWarningLabelsIfNeeded(force: false)
        guard case .skippedAlreadyComputed(let skippedWeek) = second else {
            return XCTFail("Expected skippedAlreadyComputed, got \(second)")
        }
        XCTAssertEqual(skippedWeek, weekId)

        let refreshed = try await client.recomputeWarningLabelsIfNeeded(
            force: false,
            refreshSameWeek: true
        )
        guard case .computed(let refreshedWeek, _, let note) = refreshed else {
            return XCTFail("Expected computed with refreshSameWeek, got \(refreshed)")
        }
        XCTAssertEqual(refreshedWeek, weekId)
        XCTAssertTrue(note.contains("重跑本周") || note.contains("入池"))

        let labels = try await client.loadLatestLabelDecisionsByProductId()
        XCTAssertEqual(labels["1001"], LabelEngineConstants.labelObservation)
    }

    func testForceResetClearsHistoryAndRecomputes() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting()
        try await seedSixWeeksAds(client: client, productId: "1001")
        _ = try await client.recomputeWarningLabelsIfNeeded(force: false)

        let forced = try await client.recomputeWarningLabelsIfNeeded(force: true)
        guard case .computed(_, _, let note) = forced else {
            return XCTFail("Expected computed after force, got \(forced)")
        }
        XCTAssertTrue(note.contains("重置"))
    }

    // MARK: - Helpers

    private func apply(
        row: LabelProductMetricsRow,
        prev: LabelSnapshotProductState,
        thresholds: LabelMetricsThresholds? = nil
    ) -> LabelProductDecision {
        let metrics = LabelMetricsResult(
            weekStarts: weekStarts,
            currentWeekStart: weekStarts.last!,
            products: [row],
            categories: [],
            thresholds: thresholds ?? self.thresholds
        )
        let result = LabelStateMachine.apply(
            metrics: metrics,
            previousProducts: [row.productId: prev],
            historyNote: "test"
        )
        return result.decisions[0]
    }

    private func makeRow(
        clicks: Int,
        roi: Double,
        margin: Double,
        active3: Int,
        conversions: Double,
        wgs: Double = 5_000,
        isNew: Bool,
        noConvGSCurrent: Bool = false,
        dataNormal: Bool = true
    ) -> LabelProductMetricsRow {
        LabelProductMetricsRow(
            productId: "A1",
            primaryCMS3: "Cat",
            firstListedAt: isNew ? "2026-05-01" : "2025-01-01",
            cost6wCents: 10_000,
            impressions6w: 0,
            clicks6w: clicks,
            conversions6w: conversions,
            conversionValue6wCents: 10_000,
            grossSales6wCents: Int(wgs),
            grossProfit6wCents: 4_000,
            weeksWithData: 6,
            weightedCostCents: 10_000,
            weightedConversionValueCents: roi * 10_000,
            weightedGrossSalesCents: wgs,
            weightedGrossProfitCents: margin * 10_000,
            weightedAdROI: roi,
            weightedMarginReturn: margin,
            realizedMarginRate: 0.4,
            activeWeeksRecent3: active3,
            activeCurrentWeek: !noConvGSCurrent,
            noConvGSCurrentWeek: noConvGSCurrent,
            isNewByFirstListed3m: isNew,
            dataNormal: dataNormal,
            categorySampleSufficient: false,
            categoryBenchmarkROI: nil,
            categoryInsufficientReason: "test",
            benchmarkSource: LabelEngineConstants.benchmarkSourceSite,
            appliedBenchmarkROI: 1.0
        )
    }

    private func seedSixWeeksAds(client: DatabaseClient, productId: String) async throws {
        let merchantURL = try writeTemp(
            name: "m.tsv",
            contents: """
            标题\t序号\tcanonical link\t图片链接\t自定义标签 0\t自定义标签 1\t自定义标签 2\t自定义标签 3\t自定义标签 4\tgoogle 商品类别
            Item\tS\(productId)\thttps://example.com\thttps://example.com/a.jpg\tEN\t\t\t\t\tApparel & Accessories > Clothing > Dresses
            """
        )
        var ads = [
            "Ador - 产品数据",
            "2026-05-24 - 2026-07-04",
            "天\t产品 ID\t广告系列\t货币代码\t费用\t展示次数\t点击次数\t转化次数\t转化价值",
        ]
        for week in weekStarts {
            ads.append("\(week)\tS\(productId)\tC\tUSD\t1.00\t10\t1\t0.0\t$0.50")
        }
        // 周六收尾，使最近完整周锚定为 2026-06-28 起的一周
        ads.append("2026-07-04\tS\(productId)\tC\tUSD\t1.00\t10\t1\t0.0\t$0.50")
        let adsURL = try writeTemp(name: "a.csv", contents: ads.joined(separator: "\n") + "\n")
        defer {
            try? FileManager.default.removeItem(at: merchantURL)
            try? FileManager.default.removeItem(at: adsURL)
        }
        _ = try await MerchantCenterImporter(databaseClient: client)
            .importFile(sourceURL: merchantURL) { _ in }
        _ = try await AdsProductImporter(databaseClient: client)
            .importFile(sourceURL: adsURL) { _ in }
        try await client.rebuildProductWeeklyMetrics()
    }

    private func writeTemp(name: String, contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_" + name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
