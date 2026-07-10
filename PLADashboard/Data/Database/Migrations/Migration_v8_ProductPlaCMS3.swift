import Foundation
import GRDB

/// 投放明细 CMS3 写入产品维表，供标签类目基准使用。
enum Migration_v8_ProductPlaCMS3 {
    static func migrate(_ db: Database) throws {
        try db.execute(sql: """
            ALTER TABLE products ADD COLUMN pla_cms3 TEXT;
            """)
    }
}
