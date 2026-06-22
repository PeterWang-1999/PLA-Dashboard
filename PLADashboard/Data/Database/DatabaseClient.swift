import Foundation
import GRDB

actor DatabaseClient {
    let dbQueue: DatabaseQueue

    static let databaseDirectoryName = "PLA Dashboard"
    static let databaseFileName = "pla_dashboard.sqlite"

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    static func make() throws -> DatabaseClient {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport.appendingPathComponent(databaseDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let databaseURL = directory.appendingPathComponent(databaseFileName)
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON;")
            try db.execute(sql: "PRAGMA journal_mode = WAL;")
        }

        let queue = try DatabaseQueue(path: databaseURL.path, configuration: config)

        return DatabaseClient(dbQueue: queue)
    }

    /// 内存数据库，供单元测试使用。
    static func makeInMemoryForTesting() throws -> DatabaseClient {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON;")
        }
        let queue = try DatabaseQueue(configuration: config)
        try AppDatabaseMigrator.migrate(queue)
        return DatabaseClient(dbQueue: queue)
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
}

private struct DatabaseClientKey: EnvironmentKey {
    static let defaultValue: DatabaseClient? = nil
}

import SwiftUI

extension EnvironmentValues {
    var databaseClient: DatabaseClient? {
        get { self[DatabaseClientKey.self] }
        set { self[DatabaseClientKey.self] = newValue }
    }
}
