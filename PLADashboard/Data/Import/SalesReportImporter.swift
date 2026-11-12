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
        additionalSyncFiles: [URL] = [],
        incrementalSync: Bool = false,
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
            message: incrementalSync ? "正在准备导入…" : "正在复制文件…"
        ))

        let staging = incrementalSync ? nil : try ImportStagingStore.stage(
            sourceURL: sourceURL,
            accountID: databaseClient.accountID,
            importId: importId,
            fileName: fileName
        )

        if let staging, let existing = try await databaseClient.findImportJobByChecksum(staging.checksum) {
            throw ImportPipelineError.duplicateFile(existingJobId: existing.id)
        }

        var job = ImportJobRecord(
            id: importId,
            sourceKind: ImportSourceKind.salesReport.rawValue,
            fileName: staging?.fileName ?? fileName ?? "BI Data · Product Sales",
            filePathBookmark: staging?.bookmarkData,
            fileChecksum: staging?.checksum,
            importedAt: importedAt,
            status: ImportJobStatus.running.rawValue,
            totalRows: 0,
            validRows: 0,
            invalidRows: 0,
            warningRows: 0,
            schemaVersion: DatabaseClient.currentImportSchemaVersion
        )
        try await databaseClient.createImportJob(job)

        let input = staging?.stagedFileURL ?? sourceURL
        let files = [input] + additionalSyncFiles
        var columnMap: SalesColumnMap?
        var salesBatch: [SalesDailyRecord] = []
        var lsinBatch: [(productId: String, lsin: String)] = []
        var errorBatch: [ImportRowErrorRecord] = []
        var processedRows = 0
        var validRows = 0
        var invalidRows = 0
        var warningRows = 0

        do {
            let estimatedTotalRows = try files.reduce(0) { total, file in
                try total + DelimitedFileLineCounter.estimateDataRowCount(fileURL: file)
            }
            for file in files {
                try Task.checkCancellation()
                let separator = try DelimitedFileSniffer.detectSeparator(fileURL: file)
                let parser = StreamingDelimitedParser(fileURL: file, delimiter: separator)
                let rowOffset = processedRows
                columnMap = nil
                try await parser.forEachEvent { event in
                    try Task.checkCancellation()

                    switch event {
                    case .header(let headers):
                        columnMap = try SalesColumnMap(headers: headers)
                        await onProgress(ImportProgress(
                            phase: .parsing,
                            processedRows: processedRows,
                            totalRowsEstimate: estimatedTotalRows > 0 ? estimatedTotalRows : nil,
                            validRows: validRows,
                            invalidRows: invalidRows,
                            warningRows: warningRows,
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
                                rowNumber: rowOffset + rowNumber,
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
                                rowNumber: rowOffset + rowNumber,
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
                                rowNumber: rowOffset + rowNumber,
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
                                rowNumber: rowOffset + rowNumber,
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
                                rowNumber: rowOffset + rowNumber,
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
                                rowNumber: rowOffset + rowNumber,
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
                                rowNumber: rowOffset + rowNumber,
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
                        if !incrementalSync {
                            lsinBatch.append((productId: normalized.productID, lsin: normalized.rawValue))
                        }
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
            }
            if incrementalSync, invalidRows > 0 {
                try await appendErrors(&errorBatch, importId: importId, force: true)
                let errors = try await databaseClient.fetchImportErrors(importId: importId, limit: 10)
                let first = errors.first { $0.severity == ImportRowSeverity.error.rawValue }
                let detail = first.map { "（第 \($0.rowNumber) 行：\($0.message)）" } ?? ""
                throw ImportPipelineError.invalidSyncData("Product Sales 有 \(invalidRows) 行无法导入\(detail)。")
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
            if incrementalSync {
                await onProgress(.fromJob(phase: .finalizing, job: job, message: "正在提交 Product Sales 数据…"))
                try Task.checkCancellation()
                try await databaseClient.finishSalesSync(job)
                return ImportResult(importId: importId, stagedFileURL: input, job: job, errors: [])
            }
            try await databaseClient.updateImportJob(job)

            let errors = try await databaseClient.fetchImportErrors(importId: importId)
            return ImportResult(importId: importId, stagedFileURL: input, job: job, errors: errors)
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
