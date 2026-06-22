import Foundation
import GRDB

struct AdsProductDailyRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "ads_product_daily"

    var date: String
    var itemId: String
    var productId: String
    var variantId: String?
    var campaign: String
    var currencyCode: String
    var costMicros: Int
    var impressions: Int
    var clicks: Int
    var conversions: Double
    var conversionValueCents: Int
    var importId: String

    enum Columns: String, ColumnExpression {
        case date
        case itemId = "item_id"
        case productId = "product_id"
        case variantId = "variant_id"
        case campaign
        case currencyCode = "currency_code"
        case costMicros = "cost_micros"
        case impressions
        case clicks
        case conversions
        case conversionValueCents = "conversion_value_cents"
        case importId = "import_id"
    }

    enum CodingKeys: String, CodingKey {
        case date
        case itemId = "item_id"
        case productId = "product_id"
        case variantId = "variant_id"
        case campaign
        case currencyCode = "currency_code"
        case costMicros = "cost_micros"
        case impressions
        case clicks
        case conversions
        case conversionValueCents = "conversion_value_cents"
        case importId = "import_id"
    }
}
