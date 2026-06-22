import Foundation
import GRDB

struct MerchantItemRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "merchant_items"

    var importId: String
    var itemId: String
    var productId: String
    var variantId: String?
    var title: String?
    var canonicalLink: String?
    var imageUrl: String?
    var customLabel0: String?
    var customLabel1: String?
    var customLabel2: String?
    var customLabel3: String?
    var customLabel4: String?

    enum Columns: String, ColumnExpression {
        case importId = "import_id"
        case itemId = "item_id"
        case productId = "product_id"
        case variantId = "variant_id"
        case title
        case canonicalLink = "canonical_link"
        case imageUrl = "image_url"
        case customLabel0 = "custom_label_0"
        case customLabel1 = "custom_label_1"
        case customLabel2 = "custom_label_2"
        case customLabel3 = "custom_label_3"
        case customLabel4 = "custom_label_4"
    }

    enum CodingKeys: String, CodingKey {
        case importId = "import_id"
        case itemId = "item_id"
        case productId = "product_id"
        case variantId = "variant_id"
        case title
        case canonicalLink = "canonical_link"
        case imageUrl = "image_url"
        case customLabel0 = "custom_label_0"
        case customLabel1 = "custom_label_1"
        case customLabel2 = "custom_label_2"
        case customLabel3 = "custom_label_3"
        case customLabel4 = "custom_label_4"
    }
}
