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
        migrator.registerMigration("v12_product_pla_category_path") { db in
            try db.execute(sql: "ALTER TABLE products ADD COLUMN pla_category_path TEXT;")
        }
        migrator.registerMigration("v13_pla_product_tags") { db in
            try db.execute(sql: """
                CREATE TABLE pla_product_tag_snapshots (
                    product_id TEXT PRIMARY KEY NOT NULL,
                    report_day TEXT NOT NULL
                );
                CREATE TABLE pla_product_tags (
                    product_id TEXT NOT NULL REFERENCES pla_product_tag_snapshots(product_id) ON DELETE CASCADE,
                    tag TEXT NOT NULL,
                    PRIMARY KEY (product_id, tag)
                );
                CREATE INDEX idx_pla_product_tags_tag ON pla_product_tags(tag);
                """)
        }

        if let target {
            try migrator.migrate(dbQueue, upTo: target)
        } else {
            try migrator.migrate(dbQueue)
        }
    }
}
