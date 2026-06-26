import Foundation
import GRDB

/// 将自建站 Merchant 导入遗留的 `S` 前缀 product_id 与 Ads/LSIN 使用的数字 ID 对齐。
enum Migration_v5_LsinProductIDReconciliation {
    static func migrate(_ db: Database) throws {
        let prefixedIDs = try String.fetchAll(db, sql: """
            SELECT product_id
            FROM products
            WHERE product_id GLOB 'S[0-9]*'
              AND length(product_id) > 1;
            """)

        guard !prefixedIDs.isEmpty else { return }

        var didMutate = false

        for prefixedID in prefixedIDs {
            guard prefixedID.first?.uppercased() == "S" else { continue }
            let numericID = String(prefixedID.dropFirst())
            guard !numericID.isEmpty, numericID.allSatisfy(\.isNumber) else { continue }

            if var numericProduct = try ProductRecord.fetchOne(db, key: numericID),
               let prefixedProduct = try ProductRecord.fetchOne(db, key: prefixedID) {
                ProductCatalogMerge.merge(into: &numericProduct, from: prefixedProduct)
                try numericProduct.update(db)
                try db.execute(
                    sql: "DELETE FROM products WHERE product_id = ?;",
                    arguments: [prefixedID]
                )
                try db.execute(
                    sql: "UPDATE merchant_items SET product_id = ? WHERE product_id = ?;",
                    arguments: [numericID, prefixedID]
                )
                didMutate = true
                continue
            }

            try db.execute(
                sql: "UPDATE products SET product_id = ? WHERE product_id = ?;",
                arguments: [numericID, prefixedID]
            )
            try db.execute(
                sql: "UPDATE merchant_items SET product_id = ? WHERE product_id = ?;",
                arguments: [numericID, prefixedID]
            )
            try db.execute(
                sql: "UPDATE ads_product_daily SET product_id = ? WHERE product_id = ?;",
                arguments: [numericID, prefixedID]
            )
            try db.execute(
                sql: "UPDATE product_weekly_metrics SET product_id = ? WHERE product_id = ?;",
                arguments: [numericID, prefixedID]
            )
            try db.execute(
                sql: "UPDATE sales_daily SET product_id = ? WHERE product_id = ?;",
                arguments: [numericID, prefixedID]
            )
            didMutate = true
        }

        guard didMutate else { return }

        try db.execute(sql: "DELETE FROM product_search;")
        try db.execute(sql: """
            INSERT INTO product_search (
              product_id, title, canonical_link,
              custom_label_0, custom_label_1, custom_label_2,
              custom_label_3, custom_label_4
            )
            SELECT
              product_id, title, canonical_link,
              custom_label_0, custom_label_1, custom_label_2,
              custom_label_3, custom_label_4
            FROM products;
            """)
    }
}
