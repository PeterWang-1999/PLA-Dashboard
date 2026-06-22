import Foundation
import GRDB

enum ImportSourceKind: String, Codable, Sendable {
    case merchantCenter = "merchant_center"
}

enum ImportJobStatus: String, Codable, Sendable {
    case running
    case succeeded
    case failed
    case cancelled
}

struct ImportJobRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "import_jobs"

    var id: String
    var sourceKind: String
    var fileName: String
    var filePathBookmark: Data?
    var fileChecksum: String?
    var importedAt: String
    var status: String
    var totalRows: Int
    var validRows: Int
    var invalidRows: Int
    var warningRows: Int
    var schemaVersion: Int

    enum Columns: String, ColumnExpression {
        case id
        case sourceKind = "source_kind"
        case fileName = "file_name"
        case filePathBookmark = "file_path_bookmark"
        case fileChecksum = "file_checksum"
        case importedAt = "imported_at"
        case status
        case totalRows = "total_rows"
        case validRows = "valid_rows"
        case invalidRows = "invalid_rows"
        case warningRows = "warning_rows"
        case schemaVersion = "schema_version"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sourceKind = "source_kind"
        case fileName = "file_name"
        case filePathBookmark = "file_path_bookmark"
        case fileChecksum = "file_checksum"
        case importedAt = "imported_at"
        case status
        case totalRows = "total_rows"
        case validRows = "valid_rows"
        case invalidRows = "invalid_rows"
        case warningRows = "warning_rows"
        case schemaVersion = "schema_version"
    }

    var sourceKindValue: ImportSourceKind? {
        ImportSourceKind(rawValue: sourceKind)
    }

    var statusValue: ImportJobStatus? {
        ImportJobStatus(rawValue: status)
    }
}
