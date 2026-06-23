import Foundation
import GRDB

enum Migration_v3_ProductCategory {
    static func migrate(_ db: Database) throws {
        try db.execute(sql: """
            ALTER TABLE products ADD COLUMN google_product_category TEXT;
            """)

        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_products_google_category
            ON products(google_product_category);
            """)
    }
}
