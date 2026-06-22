import Foundation
import GRDB

enum ImportRowSeverity: String, Codable, Sendable {
    case error
    case warning
}

struct ImportRowErrorRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "import_row_errors"

    var id: Int64?
    var importId: String
    var rowNumber: Int
    var severity: String
    var fieldName: String?
    var message: String
    var rawValue: String?

    enum Columns: String, ColumnExpression {
        case id
        case importId = "import_id"
        case rowNumber = "row_number"
        case severity
        case fieldName = "field_name"
        case message
        case rawValue = "raw_value"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case importId = "import_id"
        case rowNumber = "row_number"
        case severity
        case fieldName = "field_name"
        case message
        case rawValue = "raw_value"
    }

    var severityValue: ImportRowSeverity? {
        ImportRowSeverity(rawValue: severity)
    }
}
