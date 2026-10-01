import GRDB

/// 退役预警专用数据；历史迁移继续保留，保证已有账户按原顺序升级。
enum Migration_v10_RemoveWarningLabels {
    static func migrate(_ db: Database) throws {
        try db.execute(sql: "DROP TABLE IF EXISTS label_snapshot_products;")
        try db.execute(sql: "DROP TABLE IF EXISTS label_snapshots;")
        try db.execute(sql: "ALTER TABLE product_weekly_metrics DROP COLUMN warning_label;")
    }
}
