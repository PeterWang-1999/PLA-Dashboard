import Foundation
import GRDB

extension Database {
    /// 单事务内批量 `INSERT OR REPLACE`（GRDB `execute` + `PersistableRecord.insert`）。
    func insertRecords<Record: PersistableRecord>(
        _ records: [Record],
        onConflict: Database.ConflictResolution = .replace
    ) throws {
        for record in records {
            try record.insert(self, onConflict: onConflict)
        }
    }

    /// Ads 日事实表多行 `INSERT OR REPLACE`（减少语句往返）。
    func bulkInsertAdsProductDaily(_ rows: [AdsProductDailyRecord]) throws {
        guard !rows.isEmpty else { return }
        let columnCount = 12
        let maxRowsPerStatement = 80
        for chunkStart in stride(from: 0, to: rows.count, by: maxRowsPerStatement) {
            let chunk = Array(rows[chunkStart..<min(chunkStart + maxRowsPerStatement, rows.count)])
            let valuePlaceholders = Array(repeating: "(?,?,?,?,?,?,?,?,?,?,?,?)", count: chunk.count)
                .joined(separator: ", ")
            let sql = """
                INSERT OR REPLACE INTO ads_product_daily (
                  date, item_id, product_id, variant_id, campaign, currency_code,
                  cost_micros, impressions, clicks, conversions, conversion_value_cents, import_id
                ) VALUES \(valuePlaceholders);
                """
            var arguments = StatementArguments()
            for row in chunk {
                arguments += [
                    row.date,
                    row.itemId,
                    row.productId,
                    row.variantId,
                    row.campaign,
                    row.currencyCode,
                    row.costMicros,
                    row.impressions,
                    row.clicks,
                    row.conversions,
                    row.conversionValueCents,
                    row.importId,
                ]
            }
            _ = columnCount
            try execute(sql: sql, arguments: arguments)
        }
    }

    /// Sales 日事实表多行 `INSERT OR REPLACE`，显式写入毛利列，避免 Codable 漏列。
    func bulkInsertSalesDaily(_ rows: [SalesDailyRecord]) throws {
        guard !rows.isEmpty else { return }
        let maxRowsPerStatement = 100
        for chunkStart in stride(from: 0, to: rows.count, by: maxRowsPerStatement) {
            let chunk = Array(rows[chunkStart..<min(chunkStart + maxRowsPerStatement, rows.count)])
            let valuePlaceholders = Array(repeating: "(?,?,?,?,?,?)", count: chunk.count)
                .joined(separator: ", ")
            let sql = """
                INSERT OR REPLACE INTO sales_daily (
                  date, lsin, product_id, gross_sales_cents, gross_profit_cents, import_id
                ) VALUES \(valuePlaceholders);
                """
            var arguments = StatementArguments()
            for row in chunk {
                arguments += [
                    row.date,
                    row.lsin,
                    row.productId,
                    row.grossSalesCents,
                    row.grossProfitCents,
                    row.importId,
                ]
            }
            try execute(sql: sql, arguments: arguments)
        }
    }
}
