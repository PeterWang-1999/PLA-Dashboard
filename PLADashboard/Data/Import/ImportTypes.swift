import Foundation

struct ImportProgress: Sendable {
    enum Phase: Sendable {
        case staging
        case parsing
        case writing
        case finalizing
        case completed
        case failed
        case cancelled
    }

    let phase: Phase
    let processedRows: Int
    let totalRowsEstimate: Int?
    let validRows: Int
    let invalidRows: Int
    let warningRows: Int
    let message: String?

    var fractionCompleted: Double? {
        guard let totalRowsEstimate, totalRowsEstimate > 0 else { return nil }
        return min(1, Double(processedRows) / Double(totalRowsEstimate))
    }
}

struct ImportResult: Sendable {
    let importId: String
    let stagedFileURL: URL
    let job: ImportJobRecord
    let errors: [ImportRowErrorRecord]
}

enum ImportPipelineError: Error, LocalizedError {
    case duplicateFile(existingJobId: String)
    case missingRequiredColumns(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .duplicateFile(let id):
            "该文件已导入过（批次 \(id)）"
        case .missingRequiredColumns(let message):
            message
        case .cancelled:
            "导入已取消"
        }
    }
}

typealias MerchantCenterImportError = ImportPipelineError
