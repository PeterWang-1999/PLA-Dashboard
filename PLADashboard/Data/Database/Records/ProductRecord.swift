import Foundation
import GRDB

struct ProductRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "products"

    var productId: String
    var title: String?
    var canonicalLink: String?
    var imageUrl: String?
    var customLabel0: String?
    var customLabel1: String?
    var customLabel2: String?
    var customLabel3: String?
    var customLabel4: String?
    var lsin: String?
    var googleProductCategory: String?
    var firstSeenAt: String?
    var lastSeenAt: String?
    var updatedFromImportId: String?

    var id: String { productId }

    enum Columns: String, ColumnExpression {
        case productId = "product_id"
        case title
        case canonicalLink = "canonical_link"
        case imageUrl = "image_url"
        case customLabel0 = "custom_label_0"
        case customLabel1 = "custom_label_1"
        case customLabel2 = "custom_label_2"
        case customLabel3 = "custom_label_3"
        case customLabel4 = "custom_label_4"
        case lsin
        case googleProductCategory = "google_product_category"
        case firstSeenAt = "first_seen_at"
        case lastSeenAt = "last_seen_at"
        case updatedFromImportId = "updated_from_import_id"
    }

    enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case title
        case canonicalLink = "canonical_link"
        case imageUrl = "image_url"
        case customLabel0 = "custom_label_0"
        case customLabel1 = "custom_label_1"
        case customLabel2 = "custom_label_2"
        case customLabel3 = "custom_label_3"
        case customLabel4 = "custom_label_4"
        case lsin
        case googleProductCategory = "google_product_category"
        case firstSeenAt = "first_seen_at"
        case lastSeenAt = "last_seen_at"
        case updatedFromImportId = "updated_from_import_id"
    }

    var customLabels: [String?] {
        [customLabel0, customLabel1, customLabel2, customLabel3, customLabel4]
    }

    /// 字段完整度评分，用于合并冲突时选主记录。
    func completenessScore() -> Int {
        var score = 0
        if let title, !title.isEmpty { score += 2 }
        if let canonicalLink, !canonicalLink.isEmpty { score += 2 }
        if let imageUrl, !imageUrl.isEmpty { score += 2 }
        score += customLabels.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
        if let googleProductCategory, !googleProductCategory.isEmpty { score += 1 }
        return score
    }
}
