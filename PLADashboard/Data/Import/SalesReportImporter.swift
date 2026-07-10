import Foundation

actor SalesReportImporter {
    private var batchSize: Int { BenchmarkConfiguration.importBatchSize }

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
            accountID: databaseClient.accountID,
            importId: importId,
            fileName: fileName
        )

        if let existing = try await databaseClient.findImportJobByChecksum(staging.checksum) {
            throw ImportPipelineError.duplicateFile(existingJobId: existing.id)
        }

        var job = ImportJobRecord(
            id: importId,
            sourceKind: ImportSourceKind.salesReport.rawValue,
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

        let separator = try DelimitedFileSniffer.detectSeparator(fileURL: staging.stagedFileURL)

        await onProgress(ImportProgress(
            phase: .parsing,
            processedRows: 0,
            totalRowsEstimate: nil,
            validRows: 0,
            invalidRows: 0,
            warningRows: 0,
            message: "正在统计行数…"
        ))

        let estimatedTotalRows = try DelimitedFileLineCounter.estimateDataRowCount(
            fileURL: staging.stagedFileURL
        )

        let parser = StreamingDelimitedParser(fileURL: staging.stagedFileURL, delimiter: separator)

        var columnMap: SalesColumnMap?
        var salesBatch: [SalesDailyRecord] = []
        var lsinBatch: [(productId: String, lsin: String)] = []
        var errorBatch: [ImportRowErrorRecord] = []
        var processedRows = 0
        var validRows = 0
        var invalidRows = 0
        var warningRows = 0

        do {
            try await parser.forEachEvent { event in
                try Task.checkCancellation()

                switch event {
                case .header(let headers):
                    columnMap = try SalesColumnMap(headers: headers)
                    await onProgress(ImportProgress(
                        phase: .parsing,
                        processedRows: 0,
                        totalRowsEstimate: estimatedTotalRows > 0 ? estimatedTotalRows : nil,
                        validRows: 0,
                        invalidRows: 0,
                        warningRows: 0,
                        message: "正在解析 CSV…"
                    ))

                case .row(let rowNumber, let fields):
                    processedRows += 1
                    guard let columnMap else {
                        throw StreamingDelimitedParserError.missingHeader
                    }

                    guard let lsinRaw = columnMap.value(at: columnMap.lsinIndex, in: fields) else {
                        invalidRows += 1
                        errorBatch.append(makeError(
                            importId: importId,
                            rowNumber: rowNumber,
                            severity: .error,
                            fieldName: "LSIN",
                            message: "LSIN 为空",
                            rawValue: nil
                        ))
                        try await appendErrors(&errorBatch, importId: importId)
                        return
                    }

                    if lsinRaw.compare("Total", options: .caseInsensitive) == .orderedSame {
                        warningRows += 1
                        errorBatch.append(makeError(
                            importId: importId,
                            rowNumber: rowNumber,
                            severity: .warning,
                            fieldName: "LSIN",
                            message: "汇总行已跳过",
                            rawValue: lsinRaw
                        ))
                        try await appendErrors(&errorBatch, importId: importId)
                        return
                    }

                    guard let dateRaw = columnMap.value(at: columnMap.dateIndex, in: fields),
                          let isoDate = ImportValueParsers.parseISODate(dateRaw) else {
                        invalidRows += 1
                        errorBatch.append(makeError(
                            importId: importId,
                            rowNumber: rowNumber,
                            severity: .error,
                            fieldName: "日期",
                            message: "无法解析日期",
                            rawValue: columnMap.value(at: columnMap.dateIndex, in: fields)
                        ))
                        try await appendErrors(&errorBatch, importId: importId)
                        return
                    }

                    guard let grossRaw = columnMap.value(at: columnMap.grossSalesIndex, in: fields),
                          let grossCents = ImportValueParsers.parseCurrencyToCents(grossRaw) else {
                        invalidRows += 1
                        errorBatch.append(makeError(
                            importId: importId,
                            rowNumber: rowNumber,
                            severity: .error,
                            fieldName: "Gross Sales($)",
                            message: "无法解析金额",
                            rawValue: columnMap.value(at: columnMap.grossSalesIndex, in: fields)
                        ))
                        try await appendErrors(&errorBatch, importId: importId)
                        return
                    }

                    guard let profitRaw = columnMap.value(at: columnMap.grossProfitIndex, in: fields),
                          let profitCents = ImportValueParsers.parseCurrencyToCents(profitRaw) else {
                        invalidRows += 1
                        errorBatch.append(makeError(
                            importId: importId,
                            rowNumber: rowNumber,
                            severity: .error,
                            fieldName: "毛利额($)",
                            message: "无法解析毛利额",
                            rawValue: columnMap.value(at: columnMap.grossProfitIndex, in: fields)
                        ))
                        try await appendErrors(&errorBatch, importId: importId)
                        return
                    }

                    let normalized = ProductIDNormalizer.normalizeLSIN(lsinRaw)
                    guard !normalized.productID.isEmpty else {
                        invalidRows += 1
                        errorBatch.append(makeError(
                            importId: importId,
                            rowNumber: rowNumber,
                            severity: .error,
                            fieldName: "LSIN",
                            message: "无法解析产品 ID",
                            rawValue: lsinRaw
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
                            fieldName: "LSIN",
                            message: "LSIN 使用回退规则解析产品 ID",
                            rawValue: lsinRaw
                        ))
                    }

                    salesBatch.append(SalesDailyRecord(
                        date: isoDate,
                        lsin: normalized.rawValue,
                        productId: normalized.productID,
                        grossSalesCents: grossCents,
                        grossProfitCents: profitCents,
                        importId: importId
                    ))
                    lsinBatch.append((productId: normalized.productID, lsin: normalized.rawValue))
                    validRows += 1

                    if salesBatch.count >= batchSize {
                        try await flushBatches(
                            salesBatch: &salesBatch,
                            lsinBatch: &lsinBatch,
                            importId: importId,
                            importedAt: importedAt
                        )
                    }

                    try await appendErrors(&errorBatch, importId: importId)

                    if processedRows.isMultiple(of: 100) {
                        await onProgress(ImportProgress(
                            phase: .writing,
                            processedRows: processedRows,
                            totalRowsEstimate: estimatedTotalRows > 0 ? estimatedTotalRows : nil,
                            validRows: validRows,
                            invalidRows: invalidRows,
                            warningRows: warningRows,
                            message: nil
                        ))
                    }
                }
            }

            guard columnMap != nil else {
                throw StreamingDelimitedParserError.missingHeader
            }

            try await flushBatches(
                salesBatch: &salesBatch,
                lsinBatch: &lsinBatch,
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

            let errors = try await databaseClient.fetchImportErrors(importId: importId)
            return ImportResult(importId: importId, stagedFileURL: staging.stagedFileURL, job: job, errors: errors)
        } catch is CancellationError {
            try? await databaseClient.rollbackImport(importId: importId, sourceKind: .salesReport)
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
            throw ImportPipelineError.cancelled
        } catch {
            try? await databaseClient.rollbackImport(importId: importId, sourceKind: .salesReport)
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
        salesBatch: inout [SalesDailyRecord],
        lsinBatch: inout [(productId: String, lsin: String)],
        importId: String,
        importedAt: String
    ) async throws {
        guard !salesBatch.isEmpty else { return }
        try await databaseClient.insertSalesDailyBatch(salesBatch)
        try await databaseClient.upsertProductLSINBatch(lsinBatch, importId: importId, importedAt: importedAt)
        salesBatch.removeAll(keepingCapacity: true)
        lsinBatch.removeAll(keepingCapacity: true)
    }

    private func appendErrors(
        _ errors: inout [ImportRowErrorRecord],
        importId: String,
        force: Bool = false
    ) async throws {
        guard force || errors.count >= batchSize else { return }
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
