import Foundation
import GRDB

/// 预警标签引擎数据地基：毛利额、首次上架时间、周表毛利列。
enum Migration_v6_LabelEngineDataFoundation {
    static func migrate(_ db: Database) throws {
        try db.execute(sql: """
            ALTER TABLE sales_daily ADD COLUMN gross_profit_cents INTEGER NOT NULL DEFAULT 0;
            """)

        try db.execute(sql: """
            ALTER TABLE product_weekly_metrics ADD COLUMN gross_profit_cents INTEGER NOT NULL DEFAULT 0;
            """)

        try db.execute(sql: """
            ALTER TABLE products ADD COLUMN first_listed_at TEXT;
            """)
    }
}
