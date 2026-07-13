import Foundation
import GRDB

actor DatabaseClient {
    nonisolated let accountID: String
    let dbQueue: DatabaseQueue
    private var dashboardMetricsCache: DashboardMetricsCache?
    /// 自建站最新一周标签快照缓存，避免每次翻页全表重读。
    private var cachedLabelDecisions: (weekId: String, labels: [String: String])?

    static let databaseDirectoryName = WorkspacePaths.applicationDirectoryName
    static let databaseFileName = WorkspacePaths.databaseFileName

    init(accountID: String, dbQueue: DatabaseQueue) {
        self.accountID = accountID
        self.dbQueue = dbQueue
    }

    static func make(accountID: String) throws -> DatabaseClient {
        let databaseURL = try WorkspacePaths.databaseURL(accountID: accountID)
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON;")
            try db.execute(sql: "PRAGMA journal_mode = WAL;")
        }

        let queue = try DatabaseQueue(path: databaseURL.path, configuration: config)
        try AppDatabaseMigrator.migrate(queue)
        return DatabaseClient(accountID: accountID, dbQueue: queue)
    }

    static func make() throws -> DatabaseClient {
        let manifest = try WorkspaceAccountPersistence.loadOrCreateManifest()
        return try make(accountID: manifest.activeAccountID)
    }

    /// 内存数据库，供单元测试使用。
    static func makeInMemoryForTesting() throws -> DatabaseClient {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON;")
        }
        let queue = try DatabaseQueue(configuration: config)
        try AppDatabaseMigrator.migrate(queue)
        return DatabaseClient(accountID: "in-memory-test", dbQueue: queue)
    }

    func migrateIfNeeded() throws {
        try AppDatabaseMigrator.migrate(dbQueue)
    }

    func currentSchemaVersion() throws -> Int {
        try dbQueue.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT COALESCE(MAX(version), 0) AS version
                FROM grdb_migrations;
                """)
            return row?["version"] ?? 0
        }
    }

    func productWeeklyMetricsCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM product_weekly_metrics;") ?? 0
        }
    }

    func invalidateDashboardCache() {
        dashboardMetricsCache = nil
        cachedLabelDecisions = nil
    }

    func cachedDashboardMetrics(for weekStarts: [String]) -> DashboardMetricsCache? {
        guard let cache = dashboardMetricsCache, cache.weekStartsKey == weekStarts.cacheKey else {
            return nil
        }
        return cache
    }

    func storeDashboardMetricsCache(_ cache: DashboardMetricsCache) {
        dashboardMetricsCache = cache
    }

    /// 按最新 `week_id` 缓存标签字典；快照变更后由 `invalidateDashboardCache` 清空。
    func cachedOrLoadLatestLabelDecisions() throws -> [String: String] {
        guard let weekId = try latestLabelSnapshotWeekId() else { return [:] }
        if let cached = cachedLabelDecisions, cached.weekId == weekId {
            return cached.labels
        }
        let labels = try loadLatestLabelDecisionsByProductId()
        cachedLabelDecisions = (weekId, labels)
        return labels
    }

    /// 合并自建站 `S` 前缀 product_id 与数字 ID（幂等，可由诊断或迁移触发）。
    func reconcileLsinPrefixedProductIDs() throws {
        try dbQueue.write { db in
            try Migration_v5_LsinProductIDReconciliation.migrate(db)
        }
        invalidateDashboardCache()
    }

    /// 清除自建站遗留的 Google Ads（`ads_product`）导入数据；投放明细写入同一事实表但 `source_kind` 不同。
    /// - Returns: 是否删除了任何行（用于决定是否重建周聚合）。
    @discardableResult
    func purgeLegacyGoogleAdsImports() throws -> Bool {
        let didDelete = try dbQueue.write { db -> Bool in
            let jobIDs = try String.fetchAll(db, sql: """
                SELECT id FROM import_jobs WHERE source_kind = ?;
                """, arguments: [ImportSourceKind.adsProduct.rawValue])
            guard !jobIDs.isEmpty else { return false }

            try db.execute(
                sql: """
                DELETE FROM ads_product_daily
                WHERE import_id IN (
                  SELECT id FROM import_jobs WHERE source_kind = ?
                );
                """,
                arguments: [ImportSourceKind.adsProduct.rawValue]
            )
            try db.execute(
                sql: """
                DELETE FROM import_row_errors
                WHERE import_id IN (
                  SELECT id FROM import_jobs WHERE source_kind = ?
                );
                """,
                arguments: [ImportSourceKind.adsProduct.rawValue]
            )
            try db.execute(
                sql: "DELETE FROM import_jobs WHERE source_kind = ?;",
                arguments: [ImportSourceKind.adsProduct.rawValue]
            )
            try db.execute(sql: "DELETE FROM product_weekly_metrics;")
            return true
        }
        if didDelete {
            invalidateDashboardCache()
        }
        return didDelete
    }
}
