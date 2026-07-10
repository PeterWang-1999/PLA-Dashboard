import Foundation
import GRDB

struct SalesDailyRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "sales_daily"

    var date: String
    var lsin: String
    var productId: String?
    var grossSalesCents: Int
    var grossProfitCents: Int
    var importId: String

    enum Columns: String, ColumnExpression {
        case date
        case lsin
        case productId = "product_id"
        case grossSalesCents = "gross_sales_cents"
        case grossProfitCents = "gross_profit_cents"
        case importId = "import_id"
    }

    enum CodingKeys: String, CodingKey {
        case date
        case lsin
        case productId = "product_id"
        case grossSalesCents = "gross_sales_cents"
        case grossProfitCents = "gross_profit_cents"
        case importId = "import_id"
    }
}
