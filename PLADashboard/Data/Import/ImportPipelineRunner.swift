import Foundation

/// 在 MainActor 之外执行导入流水线，避免阻塞 UI。
enum ImportPipelineRunner: Sendable {
    nonisolated static func importFile(
        sourceKind: ImportSourceKind,
        sourceURL: URL,
        fileName: String?,
        databaseClient: DatabaseClient,
        onProgress: @Sendable @escaping (ImportProgress) async -> Void
    ) async throws -> ImportResult {
        try Task.checkCancellation()

        switch sourceKind {
        case .merchantCenter:
            let importer = MerchantCenterImporter(databaseClient: databaseClient)
            return try await importer.importFile(
                sourceURL: sourceURL,
                fileName: fileName,
                onProgress: onProgress
            )
        case .salesReport:
            let importer = SalesReportImporter(databaseClient: databaseClient)
            return try await importer.importFile(
                sourceURL: sourceURL,
                fileName: fileName,
                onProgress: onProgress
            )
        case .adsProduct:
            let importer = AdsProductImporter(databaseClient: databaseClient)
            return try await importer.importFile(
                sourceURL: sourceURL,
                fileName: fileName,
                onProgress: onProgress
            )
        }
    }

    nonisolated static func rebuildWeeklyMetrics(databaseClient: DatabaseClient) async throws {
        try Task.checkCancellation()
        try await databaseClient.rebuildProductWeeklyMetrics()
    }
}
