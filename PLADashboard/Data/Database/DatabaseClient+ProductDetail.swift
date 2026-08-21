import Foundation
import GRDB

extension DatabaseClient {
    func fetchProductDetail(
        productID: String,
        weekStarts: [String],
        latestDataDay: String
    ) throws -> ProductDetailModel {
        guard let periodStart = weekStarts.first else {
            throw ProductDetailError.missingReportingPeriod
        }

        return try dbQueue.read { db in
            guard let product = try ProductRecord.fetchOne(db, key: productID) else {
                throw ProductDetailError.productNotFound
            }

            let rows = try Row.fetchAll(
                db,
                sql: """
                    WITH ranked_ads AS (
                      SELECT
                        a.item_id,
                        a.variant_id,
                        a.currency_code,
                        a.cost_micros,
                        a.clicks,
                        a.conversions,
                        a.conversion_value_cents,
                        ROW_NUMBER() OVER (
                          PARTITION BY a.date, a.item_id, a.campaign, a.currency_code
                          ORDER BY j.imported_at DESC
                        ) AS rn
                      FROM ads_product_daily a
                      INNER JOIN import_jobs j ON j.id = a.import_id
                      WHERE j.status = ?
                        AND a.product_id = ?
                        AND a.date >= ?
                        AND a.date <= ?
                    )
                    SELECT
                      item_id,
                      MAX(variant_id) AS variant_id,
                      MIN(currency_code) AS currency_code,
                      SUM(cost_micros) AS cost_micros,
                      SUM(clicks) AS clicks,
                      SUM(conversions) AS conversions,
                      SUM(conversion_value_cents) AS conversion_value_cents
                    FROM ranked_ads
                    WHERE rn = 1
                    GROUP BY item_id
                    ORDER BY cost_micros DESC, item_id COLLATE NOCASE ASC;
                    """,
                arguments: [
                    ImportJobStatus.succeeded.rawValue,
                    productID,
                    periodStart,
                    latestDataDay,
                ]
            )

            let skuRows = rows.map { row in
                ProductDetailSKURow(
                    itemID: row["item_id"],
                    variantID: row["variant_id"],
                    currencyCode: row["currency_code"] ?? "",
                    costMicros: row["cost_micros"] ?? 0,
                    clicks: row["clicks"] ?? 0,
                    conversions: row["conversions"] ?? 0,
                    conversionValueCents: row["conversion_value_cents"] ?? 0
                )
            }

            return ProductDetailModel(
                productID: product.productId,
                title: product.title,
                imageURL: ProductImageURLResolver.resolve(product.imageUrl),
                canonicalURL: product.canonicalLink.flatMap(URL.init(string:)),
                customLabels: product.customLabels,
                skuRows: skuRows,
                periodStart: periodStart,
                periodEnd: latestDataDay
            )
        }
    }
}
