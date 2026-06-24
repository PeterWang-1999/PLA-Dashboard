import Foundation
import GRDB

actor DatabaseClient {
    nonisolated let accountID: String
    let dbQueue: DatabaseQueue
    private var dashboardMetricsCache: DashboardMetricsCache?

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
}

private struct DatabaseClientKey: EnvironmentKey {
    static let defaultValue: DatabaseClient? = nil
}

import SwiftUI

extension EnvironmentValues {
    @MainActor
    var databaseClient: DatabaseClient? {
        get { self[DatabaseClientKey.self] }
        set { self[DatabaseClientKey.self] = newValue }
    }
}
