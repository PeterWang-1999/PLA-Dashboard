import GRDB

/// 持久记录成功导入的失效范围，收尾中断后仍可恢复。
enum Migration_v11_WeeklyMetricsRefresh {
    static func migrate(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE weekly_metrics_refresh_state (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              initialized INTEGER NOT NULL DEFAULT 0
            );
            INSERT INTO weekly_metrics_refresh_state (id, initialized) VALUES (1, 0);
            CREATE TABLE weekly_metrics_dirty_products (
              product_id TEXT PRIMARY KEY NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_sales_import_id ON sales_daily(import_id);
            """)
    }
}
