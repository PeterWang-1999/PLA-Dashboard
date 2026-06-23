import Foundation
import GRDB

enum Migration_v4_PerformanceIndexes {
    static func migrate(_ db: Database) throws {
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_import_jobs_checksum
              ON import_jobs(file_checksum);
            """)
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_import_jobs_status
              ON import_jobs(status);
            """)
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_ads_import_id
              ON ads_product_daily(import_id);
            """)
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_weekly_week_start
              ON product_weekly_metrics(week_start);
            """)
    }
}
