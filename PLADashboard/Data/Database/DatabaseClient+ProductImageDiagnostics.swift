import Foundation
import GRDB

struct ProductImageDiagnosticsReport: Sendable {
    struct SampleRow: Sendable {
        let productID: String
        let lsin: String?
        let imageURL: String?
        let note: String
    }

    let accountName: String
    let totalProducts: Int
    let productsWithImageURL: Int
    let dashboardVisibleWithoutImage: Int
    let lsinPrefixedOrphanCount: Int
    let invalidURLSamples: [SampleRow]
    let missingImageSamples: [SampleRow]

    var formattedText: String {
        var lines: [String] = []
        lines.append("账户：\(accountName)")
        lines.append("产品总数：\(totalProducts)")
        lines.append("含图片链接：\(productsWithImageURL)")
        lines.append("看板可见但无图：\(dashboardVisibleWithoutImage)")
        lines.append("S 前缀重复记录：\(lsinPrefixedOrphanCount)")

        if !invalidURLSamples.isEmpty {
            lines.append("")
            lines.append("无法解析的图片 URL（最多 5 条）：")
            for row in invalidURLSamples {
                lines.append("- \(row.productID)：\(row.imageURL ?? "—")（\(row.note)）")
            }
        }

        if !missingImageSamples.isEmpty {
            lines.append("")
            lines.append("看板可见但缺图样例（最多 5 条）：")
            for row in missingImageSamples {
                let lsinText = row.lsin ?? "—"
                lines.append("- \(row.productID) / LSIN \(lsinText)：\(row.note)")
            }
        }

        if dashboardVisibleWithoutImage > 0 {
            lines.append("")
            lines.append("建议：重新导入 Merchant Center TSV，或确认序号与 Ads 产品 ID 一致（S 前缀会自动对齐）。")
        }

        if lsinPrefixedOrphanCount > 0 {
            lines.append("建议：重启应用以执行 v5 迁移，合并 S 前缀产品记录。")
        }

        return lines.joined(separator: "\n")
    }
}

extension DatabaseClient {
    func buildProductImageDiagnosticsReport(accountName: String) throws -> ProductImageDiagnosticsReport {
        try dbQueue.read { db in
            let totalProducts = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM products;") ?? 0
            let productsWithImageURL = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM products
                WHERE image_url IS NOT NULL AND trim(image_url) != '';
                """) ?? 0

            let dashboardVisibleWithoutImage = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM (
                  SELECT DISTINCT p.product_id
                  FROM products p
                  INNER JOIN product_weekly_metrics m ON m.product_id = p.product_id
                  WHERE p.image_url IS NULL OR trim(p.image_url) = ''
                );
                """) ?? 0

            let lsinPrefixedOrphanCount = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM products p1
                WHERE p1.product_id GLOB 'S[0-9]*'
                  AND EXISTS (
                    SELECT 1 FROM products p2
                    WHERE p2.product_id = substr(p1.product_id, 2)
                  );
                """) ?? 0

            let invalidRows = try Row.fetchAll(db, sql: """
                SELECT product_id, lsin, image_url
                FROM products
                WHERE image_url IS NOT NULL AND trim(image_url) != ''
                LIMIT 200;
                """)

            var invalidURLSamples: [ProductImageDiagnosticsReport.SampleRow] = []
            for row in invalidRows {
                let productID: String = row["product_id"]
                let lsin: String? = row["lsin"]
                let imageURL: String? = row["image_url"]
                guard ProductImageURLResolver.resolve(imageURL) == nil else { continue }
                invalidURLSamples.append(
                    ProductImageDiagnosticsReport.SampleRow(
                        productID: productID,
                        lsin: lsin,
                        imageURL: imageURL,
                        note: "URL 无法解析为 https/http 绝对地址"
                    )
                )
                if invalidURLSamples.count >= 5 { break }
            }

            let missingRows = try Row.fetchAll(db, sql: """
                SELECT DISTINCT p.product_id, p.lsin
                FROM products p
                INNER JOIN product_weekly_metrics m ON m.product_id = p.product_id
                WHERE p.image_url IS NULL OR trim(p.image_url) = ''
                LIMIT 5;
                """)

            let missingImageSamples = missingRows.map { row in
                ProductImageDiagnosticsReport.SampleRow(
                    productID: row["product_id"],
                    lsin: row["lsin"],
                    imageURL: nil,
                    note: "有周聚合但 image_url 为空"
                )
            }

            return ProductImageDiagnosticsReport(
                accountName: accountName,
                totalProducts: totalProducts,
                productsWithImageURL: productsWithImageURL,
                dashboardVisibleWithoutImage: dashboardVisibleWithoutImage,
                lsinPrefixedOrphanCount: lsinPrefixedOrphanCount,
                invalidURLSamples: invalidURLSamples,
                missingImageSamples: missingImageSamples
            )
        }
    }
}
