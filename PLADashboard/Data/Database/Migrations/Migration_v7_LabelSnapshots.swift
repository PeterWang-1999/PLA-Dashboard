import Foundation
import GRDB

/// 预警标签周快照表（入池/留池/出池「连续 2 次」依赖）。
enum Migration_v7_LabelSnapshots {
    static func migrate(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS label_snapshots (
              week_id TEXT PRIMARY KEY,
              created_at TEXT NOT NULL,
              ads_weeks_json TEXT NOT NULL,
              history_note TEXT
            );
            """)

        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS label_snapshot_products (
              week_id TEXT NOT NULL,
              product_id TEXT NOT NULL,
              label TEXT NOT NULL,
              fail_high_retain INTEGER NOT NULL DEFAULT 0,
              margin_lt_1 INTEGER NOT NULL DEFAULT 0,
              no_signal_recent3 INTEGER NOT NULL DEFAULT 0,
              no_conv_gs_current_week INTEGER NOT NULL DEFAULT 0,
              roi_ge_1x INTEGER NOT NULL DEFAULT 0,
              margin_ge_1 INTEGER NOT NULL DEFAULT 0,
              weeks_in_low_sample_old INTEGER NOT NULL DEFAULT 0,
              weeks_in_potential_new INTEGER NOT NULL DEFAULT 0,
              transition_action TEXT,
              reason TEXT,
              PRIMARY KEY (week_id, product_id),
              FOREIGN KEY (week_id) REFERENCES label_snapshots(week_id) ON DELETE CASCADE
            );
            """)

        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_label_snapshot_products_label
              ON label_snapshot_products(week_id, label);
            """)
    }
}
