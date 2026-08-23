import Foundation
import GRDB

/// 产品维表新增「GMC 缺失」标记：有投放/销售数据但无 Merchant 目录记录。
enum Migration_v9_MissingInGMC {
    static func migrate(_ db: Database) throws {
        try db.execute(sql: """
            ALTER TABLE products ADD COLUMN missing_in_gmc INTEGER NOT NULL DEFAULT 0;
            """)
    }
}
