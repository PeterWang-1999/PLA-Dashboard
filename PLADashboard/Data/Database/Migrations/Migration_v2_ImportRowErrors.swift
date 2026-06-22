import Foundation
import GRDB

enum Migration_v2_ImportRowErrors {
    static func migrate(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS import_row_errors (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              import_id TEXT NOT NULL,
              row_number INTEGER NOT NULL,
              severity TEXT NOT NULL,
              field_name TEXT,
              message TEXT NOT NULL,
              raw_value TEXT
            );
            """)

        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_import_errors_job ON import_row_errors(import_id);
            """)
    }
}
