import Foundation

actor MerchantCenterImporter {
    static let batchSize = 500

    private let databaseClient: DatabaseClient

    init(databaseClient: DatabaseClient) {
        self.databaseClient = databaseClient
    }

    func importFile(
        sourceURL: URL,
        fileName: String? = nil,
        onProgress: @Sendable @escaping (ImportProgress) async -> Void
    ) async throws -> ImportResult {
        let importId = UUID().uuidString
        let importedAt = ISO8601DateFormatter().string(from: Date())

        await onProgress(ImportProgress(
            phase: .staging,
            processedRows: 0,
            totalRowsEstimate: nil,
            validRows: 0,
            invalidRows: 0,
            warningRows: 0,
            message: "正在复制文件…"
        ))

        let staging = try ImportStagingStore.stage(
            sourceURL: sourceURL,
            importId: importId,
            fileName: fileName
        )

        if let existing = try await databaseClient.findImportJobByChecksum(staging.checksum) {
            throw MerchantCenterImportError.duplicateFile(existingJobId: existing.id)
        }

        var job = ImportJobRecord(
            id: importId,
            sourceKind: ImportSourceKind.merchantCenter.rawValue,
            fileName: staging.fileName,
            filePathBookmark: staging.bookmarkData,
            fileChecksum: staging.checksum,
            importedAt: importedAt,
            status: ImportJobStatus.running.rawValue,
            totalRows: 0,
            validRows: 0,
            invalidRows: 0,
            warningRows: 0,
            schemaVersion: DatabaseClient.currentImportSchemaVersion
        )
        try await databaseClient.createImportJob(job)

        var columnMap: MerchantCenterColumnMap?
        var merchantBatch: [MerchantItemRecord] = []
        var productBatch: [ProductRecord] = []
        var errorBatch: [ImportRowErrorRecord] = []
        var processedRows = 0
        var validRows = 0
        var invalidRows = 0
        var warningRows = 0

        let parser = StreamingDelimitedParser(fileURL: staging.stagedFileURL)

        do {
            try await parser.forEachEvent { event in
                try Task.checkCancellation()

                switch event {
                case .header(let headers):
                    columnMap = try MerchantCenterColumnMap(headers: headers)
                    await onProgress(ImportProgress(
                        phase: .parsing,
                        processedRows: 0,
                        totalRowsEstimate: nil,
                        validRows: 0,
                        invalidRows: 0,
                        warningRows: 0,
                        message: "正在解析 TSV…"
                    ))

                case .row(let rowNumber, let fields):
                    processedRows += 1
                    guard let columnMap else {
                        throw StreamingDelimitedParserError.missingHeader
                    }

                    guard let itemId = columnMap.value(at: columnMap.itemIdIndex, in: fields) else {
                        invalidRows += 1
                        errorBatch.append(makeError(
                            importId: importId,
                            rowNumber: rowNumber,
                            severity: .error,
                            fieldName: "序号",
                            message: "序号为空",
                            rawValue: nil
                        ))
                        try await appendErrors(&errorBatch, importId: importId)
                        return
                    }

                    let normalized = ProductIDNormalizer.normalize(itemId)
                    guard !normalized.productID.isEmpty else {
                        invalidRows += 1
                        errorBatch.append(makeError(
                            importId: importId,
                            rowNumber: rowNumber,
                            severity: .error,
                            fieldName: "序号",
                            message: "无法解析产品 ID",
                            rawValue: itemId
                        ))
                        try await appendErrors(&errorBatch, importId: importId)
                        return
                    }

                    if normalized.confidence == .medium {
                        warningRows += 1
                        errorBatch.append(makeError(
                            importId: importId,
                            rowNumber: rowNumber,
                            severity: .warning,
                            fieldName: "序号",
                            message: "产品 ID 使用下划线前缀规则解析",
                            rawValue: itemId
                        ))
                    }

                    let category = columnMap.value(at: columnMap.categoryIndex, in: fields)

                    let merchantItem = MerchantItemRecord(
                        importId: importId,
                        itemId: itemId,
                        productId: normalized.productID,
                        variantId: normalized.variantID,
                        title: columnMap.value(at: columnMap.titleIndex, in: fields),
                        canonicalLink: columnMap.value(at: columnMap.canonicalLinkIndex, in: fields),
                        imageUrl: columnMap.value(at: columnMap.imageURLIndex, in: fields),
                        customLabel0: columnMap.customLabel(at: 0, in: fields),
                        customLabel1: columnMap.customLabel(at: 1, in: fields),
                        customLabel2: columnMap.customLabel(at: 2, in: fields),
                        customLabel3: columnMap.customLabel(at: 3, in: fields),
                        customLabel4: columnMap.customLabel(at: 4, in: fields)
                    )
                    merchantBatch.append(merchantItem)

                    productBatch.append(ProductRecord(
                        productId: normalized.productID,
                        title: merchantItem.title,
                        canonicalLink: merchantItem.canonicalLink,
                        imageUrl: merchantItem.imageUrl,
                        customLabel0: merchantItem.customLabel0,
                        customLabel1: merchantItem.customLabel1,
                        customLabel2: merchantItem.customLabel2,
                        customLabel3: merchantItem.customLabel3,
                        customLabel4: merchantItem.customLabel4,
                        lsin: nil,
                        googleProductCategory: category,
                        firstSeenAt: nil,
                        lastSeenAt: nil,
                        updatedFromImportId: nil
                    ))
                    validRows += 1

                    if merchantBatch.count >= Self.batchSize {
                        try await flushBatches(
                            merchantBatch: &merchantBatch,
                            productBatch: &productBatch,
                            importId: importId,
                            importedAt: importedAt
                        )
                    }

                    try await appendErrors(&errorBatch, importId: importId)

                    if processedRows.isMultiple(of: 100) {
                        await onProgress(ImportProgress(
                            phase: .writing,
                            processedRows: processedRows,
                            totalRowsEstimate: nil,
                            validRows: validRows,
                            invalidRows: invalidRows,
                            warningRows: warningRows,
                            message: "已处理 \(processedRows) 行"
                        ))
                    }
                }
            }

            guard columnMap != nil else {
                throw StreamingDelimitedParserError.missingHeader
            }

            try await flushBatches(
                merchantBatch: &merchantBatch,
                productBatch: &productBatch,
                importId: importId,
                importedAt: importedAt
            )
            try await appendErrors(&errorBatch, importId: importId, force: true)

            job.totalRows = processedRows
            job.validRows = validRows
            job.invalidRows = invalidRows
            job.warningRows = warningRows
            job.status = ImportJobStatus.succeeded.rawValue
            try await databaseClient.updateImportJob(job)

            await onProgress(ImportProgress(
                phase: .finalizing,
                processedRows: processedRows,
                totalRowsEstimate: processedRows,
                validRows: validRows,
                invalidRows: invalidRows,
                warningRows: warningRows,
                message: "正在更新搜索索引…"
            ))

            let productIds = try await databaseClient.fetchDistinctProductIds(importId: importId)
            let products = try await databaseClient.fetchProducts(ids: productIds)
            try await databaseClient.replaceProductSearchEntries(products)

            await onProgress(ImportProgress(
                phase: .completed,
                processedRows: processedRows,
                totalRowsEstimate: processedRows,
                validRows: validRows,
                invalidRows: invalidRows,
                warningRows: warningRows,
                message: "导入完成"
            ))

            let errors = try await databaseClient.fetchImportErrors(importId: importId)
            return ImportResult(importId: importId, stagedFileURL: staging.stagedFileURL, job: job, errors: errors)
        } catch is CancellationError {
            try? await databaseClient.rollbackImport(importId: importId, sourceKind: .merchantCenter)
            try? await databaseClient.markImportCancelled(importId: importId)
            await onProgress(ImportProgress(
                phase: .cancelled,
                processedRows: processedRows,
                totalRowsEstimate: nil,
                validRows: validRows,
                invalidRows: invalidRows,
                warningRows: warningRows,
                message: "导入已取消"
            ))
            throw MerchantCenterImportError.cancelled
        } catch {
            try? await databaseClient.rollbackImport(importId: importId, sourceKind: .merchantCenter)
            await onProgress(ImportProgress(
                phase: .failed,
                processedRows: processedRows,
                totalRowsEstimate: nil,
                validRows: validRows,
                invalidRows: invalidRows,
                warningRows: warningRows,
                message: error.localizedDescription
            ))
            throw error
        }
    }

    private func flushBatches(
        merchantBatch: inout [MerchantItemRecord],
        productBatch: inout [ProductRecord],
        importId: String,
        importedAt: String
    ) async throws {
        guard !merchantBatch.isEmpty else { return }
        try await databaseClient.insertMerchantItemsBatch(merchantBatch)
        try await databaseClient.upsertProductsBatch(productBatch, importId: importId, importedAt: importedAt)
        merchantBatch.removeAll(keepingCapacity: true)
        productBatch.removeAll(keepingCapacity: true)
    }

    private func appendErrors(
        _ errors: inout [ImportRowErrorRecord],
        importId: String,
        force: Bool = false
    ) async throws {
        guard force || errors.count >= Self.batchSize else { return }
        let batch = errors
        errors.removeAll(keepingCapacity: true)
        try await databaseClient.insertImportErrorsBatch(batch)
    }

    private func makeError(
        importId: String,
        rowNumber: Int,
        severity: ImportRowSeverity,
        fieldName: String?,
        message: String,
        rawValue: String?
    ) -> ImportRowErrorRecord {
        ImportRowErrorRecord(
            id: nil,
            importId: importId,
            rowNumber: rowNumber,
            severity: severity.rawValue,
            fieldName: fieldName,
            message: message,
            rawValue: rawValue
        )
    }
}
