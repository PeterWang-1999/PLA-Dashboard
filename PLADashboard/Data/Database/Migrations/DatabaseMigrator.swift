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
    static func migrate(_ dbQueue: DatabaseQueue, upTo target: String? = nil) throws {
        var migrator = GRDB.DatabaseMigrator()

        migrator.registerMigration("v1_initial_schema") { db in
            try Migration_v1_InitialSchema.migrate(db)
        }

        migrator.registerMigration("v2_import_row_errors") { db in
            try Migration_v2_ImportRowErrors.migrate(db)
        }

        migrator.registerMigration("v3_product_category") { db in
            try Migration_v3_ProductCategory.migrate(db)
        }

        migrator.registerMigration("v4_performance_indexes") { db in
            try Migration_v4_PerformanceIndexes.migrate(db)
        }

        migrator.registerMigration("v5_lsin_product_id_reconciliation") { db in
            try Migration_v5_LsinProductIDReconciliation.migrate(db)
        }

        migrator.registerMigration("v6_label_engine_data_foundation") { db in
            try Migration_v6_LabelEngineDataFoundation.migrate(db)
        }

        migrator.registerMigration("v7_label_snapshots") { db in
            try Migration_v7_LabelSnapshots.migrate(db)
        }

        migrator.registerMigration("v8_product_pla_cms3") { db in
            try Migration_v8_ProductPlaCMS3.migrate(db)
        }

        migrator.registerMigration("v9_missing_in_gmc") { db in
            try Migration_v9_MissingInGMC.migrate(db)
        }

        migrator.registerMigration("v10_remove_warning_labels") { db in
            try Migration_v10_RemoveWarningLabels.migrate(db)
        }

        migrator.registerMigration("v11_weekly_metrics_refresh") { db in
            try Migration_v11_WeeklyMetricsRefresh.migrate(db)
        }

        if let target {
            try migrator.migrate(dbQueue, upTo: target)
        } else {
            try migrator.migrate(dbQueue)
        }
    }
}
