import Foundation
import GRDB

enum ImportSourceKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case merchantCenter = "merchant_center"
    case salesReport = "sales_report"
    case adsProduct = "ads_product"
    case plaDeliveryDetail = "pla_delivery_detail"

    var id: String { rawValue }

    static func importPickerCases(for kind: WorkspaceAccountKind) -> [ImportSourceKind] {
        WorkspaceCapabilities.forKind(kind).importSourceKinds
    }

    var displayName: String {
        switch self {
        case .merchantCenter: "Merchant Center"
        case .salesReport: "Product Sales"
        case .adsProduct: "Google Ads"
        case .plaDeliveryDetail: "投放产品明细"
        }
    }

    var sampleResourceName: String {
        sampleResourceName(accountKind: .thirdParty)
    }

    func sampleResourceName(accountKind: WorkspaceAccountKind) -> String {
        switch self {
        case .merchantCenter:
            MerchantCenterExportFormat.sampleResourceName(for: accountKind)
        case .salesReport: "SampleSales"
        case .adsProduct: "SampleAds"
        case .plaDeliveryDetail: "SamplePlaDeliveryDetail"
        }
    }

    var sampleFileExtension: String {
        switch self {
        case .merchantCenter: "tsv"
        case .salesReport, .adsProduct, .plaDeliveryDetail: "csv"
        }
    }
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

    /// 每个数据源保留最近一次导入（要求 `jobs` 已按 `importedAt` 降序）。
    static func latestPerSourceKind(from jobs: [ImportJobRecord]) -> [ImportJobRecord] {
        var latestBySource: [String: ImportJobRecord] = [:]
        for job in jobs where latestBySource[job.sourceKind] == nil {
            latestBySource[job.sourceKind] = job
        }
        return ImportSourceKind.allCases.compactMap { latestBySource[$0.rawValue] }
    }
}
