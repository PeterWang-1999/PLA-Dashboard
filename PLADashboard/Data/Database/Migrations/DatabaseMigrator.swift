import Foundation
import GRDB

enum DatabaseMigrationError: Error, LocalizedError {
    case migrationFailed(String)

    var errorDescription: String? {
        switch self {
        case .migrationFailed(let message):
            return message
        }
    }
}

struct AppDatabaseMigrator {
    static func migrate(_ dbQueue: DatabaseQueue) throws {
        var migrator = GRDB.DatabaseMigrator()

        migrator.registerMigration("v1_initial_schema") { db in
            try Migration_v1_InitialSchema.migrate(db)
        }

        migrator.registerMigration("v2_import_row_errors") { db in
            try Migration_v2_ImportRowErrors.migrate(db)
        }

        try migrator.migrate(dbQueue)
    }
}
