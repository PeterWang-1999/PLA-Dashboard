import Foundation

/// 在 MainActor 之外执行导入流水线，避免阻塞 UI。
enum ImportPipelineRunner: Sendable {
    nonisolated static func importFile(
        sourceKind: ImportSourceKind,
        sourceURL: URL,
        fileName: String?,
        databaseClient: DatabaseClient,
        accountKind: WorkspaceAccountKind,
        onProgress: @Sendable @escaping (ImportProgress) async -> Void
    ) async throws -> ImportResult {
        try Task.checkCancellation()

        switch sourceKind {
        case .merchantCenter:
            let importer = MerchantCenterImporter(
                databaseClient: databaseClient,
                accountKind: accountKind
            )
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
        case .plaDeliveryDetail:
            let importer = PlaDeliveryDetailImporter(databaseClient: databaseClient)
            return try await importer.importFile(
                sourceURL: sourceURL,
                fileName: fileName,
                onProgress: onProgress
            )
        }
    }

    nonisolated static func finishImport(
        sourceKind: ImportSourceKind,
        result: ImportResult,
        databaseClient: DatabaseClient,
        accountKind: WorkspaceAccountKind,
        onProgress: @Sendable @escaping (ImportProgress) async -> Void,
        reloadFilterCatalogs: @Sendable @escaping () async -> Void,
        refreshDashboard: @Sendable @escaping () async -> Void
    ) async throws {
        try Task.checkCancellation()
        let job = result.job

        if sourceKind == .merchantCenter {
            await onProgress(ImportProgress.fromJob(
                phase: .rebuildingCatalogs,
                job: job,
                message: "正在更新筛选目录…"
            ))
            await reloadFilterCatalogs()
        }

        try Task.checkCancellation()

        var shouldRebuildMetrics =
            sourceKind == .adsProduct || sourceKind == .plaDeliveryDetail
        if !shouldRebuildMetrics {
            shouldRebuildMetrics = try await databaseClient.hasFactTableData()
        }
        if shouldRebuildMetrics {
            await onProgress(ImportProgress.fromJob(
                phase: .rebuildingMetrics,
                job: job,
                message: "正在重建周聚合…"
            ))
            try await databaseClient.rebuildProductWeeklyMetrics()
        }

        try Task.checkCancellation()

        if accountKind == .selfBuilt,
           shouldRebuildMetrics,
           sourceKind == .plaDeliveryDetail || sourceKind == .salesReport {
            await onProgress(ImportProgress.fromJob(
                phase: .rebuildingMetrics,
                job: job,
                message: "正在计算预警标签…"
            ))
            // 同周先导投放再导毛利、或同周重导时必须允许覆盖本周快照，否则会卡在「全普通」。
            _ = try await databaseClient.recomputeWarningLabelsIfNeeded(
                force: false,
                refreshSameWeek: true
            )
        }

        try Task.checkCancellation()

        await onProgress(ImportProgress.fromJob(
            phase: .refreshingDashboard,
            job: job,
            message: "正在刷新看板…"
        ))
        await refreshDashboard()

        await onProgress(ImportProgress.fromJob(
            phase: .completed,
            job: job,
            message: "导入完成"
        ))
    }
}
