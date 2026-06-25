import Foundation

struct ImportProgress: Sendable {
    enum Phase: Sendable {
        case staging
        case parsing
        case writing
        case indexing
        case rebuildingCatalogs
        case rebuildingMetrics
        case refreshingDashboard
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
        switch phase {
        case .staging, .indexing, .rebuildingCatalogs, .rebuildingMetrics, .refreshingDashboard, .finalizing:
            return nil
        case .parsing, .writing:
            guard let totalRowsEstimate, totalRowsEstimate > 0 else { return nil }
            return min(1, Double(processedRows) / Double(totalRowsEstimate))
        case .completed:
            guard let totalRowsEstimate, totalRowsEstimate > 0 else { return 1 }
            return 1
        case .failed, .cancelled:
            return nil
        }
    }

    static func fromJob(
        phase: Phase,
        job: ImportJobRecord,
        message: String
    ) -> ImportProgress {
        ImportProgress(
            phase: phase,
            processedRows: job.totalRows,
            totalRowsEstimate: job.totalRows > 0 ? job.totalRows : nil,
            validRows: job.validRows,
            invalidRows: job.invalidRows,
            warningRows: job.warningRows,
            message: message
        )
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
