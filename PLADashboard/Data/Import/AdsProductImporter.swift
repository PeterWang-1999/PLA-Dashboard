import Foundation

actor AdsProductImporter {
    private var batchSize: Int { BenchmarkConfiguration.importBatchSize }
    static let linesToSkip = 2

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
            throw ImportPipelineError.duplicateFile(existingJobId: existing.id)
        }

        var job = ImportJobRecord(
            id: importId,
            sourceKind: ImportSourceKind.adsProduct.rawValue,
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

        let separator = try DelimitedFileSniffer.detectSeparator(
            fileURL: staging.stagedFileURL,
            linesToSkip: Self.linesToSkip
        )
        let parser = StreamingDelimitedParser(
            fileURL: staging.stagedFileURL,
            delimiter: separator,
            linesToSkip: Self.linesToSkip
        )

        var columnMap: AdsProductColumnMap?
        var adsBatch: [AdsProductDailyRecord] = []
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
                    columnMap = try AdsProductColumnMap(headers: headers)
                    await onProgress(ImportProgress(
                        phase: .parsing,
                        processedRows: 0,
                        totalRowsEstimate: nil,
                        validRows: 0,
                        invalidRows: 0,
                        warningRows: 0,
                        message: "正在解析 Google Ads 产品数据…"
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
                            fieldName: "产品 ID",
                            message: "产品 ID 为空",
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
                            fieldName: "产品 ID",
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
                            fieldName: "产品 ID",
                            message: "产品 ID 使用下划线前缀规则解析",
                            rawValue: itemId
                        ))
                    }

                    guard let dateRaw = columnMap.value(at: columnMap.dateIndex, in: fields),
                          let isoDate = ImportValueParsers.parseISODate(dateRaw) else {
                        invalidRows += 1
                        errorBatch.append(makeError(
                            importId: importId,
                            rowNumber: rowNumber,
                            severity: .error,
                            fieldName: "天",
                            message: "无法解析日期",
                            rawValue: columnMap.value(at: columnMap.dateIndex, in: fields)
                        ))
                        try await appendErrors(&errorBatch, importId: importId)
                        return
                    }

                    guard let campaign = columnMap.value(at: columnMap.campaignIndex, in: fields) else {
                        invalidRows += 1
                        errorBatch.append(makeError(
                            importId: importId,
                            rowNumber: rowNumber,
                            severity: .error,
                            fieldName: "广告系列",
                            message: "广告系列为空",
                            rawValue: nil
                        ))
                        try await appendErrors(&errorBatch, importId: importId)
                        return
                    }

                    guard let currencyCode = columnMap.value(at: columnMap.currencyCodeIndex, in: fields) else {
                        invalidRows += 1
                        errorBatch.append(makeError(
                            importId: importId,
                            rowNumber: rowNumber,
                            severity: .error,
                            fieldName: "货币代码",
                            message: "货币代码为空",
                            rawValue: nil
                        ))
                        try await appendErrors(&errorBatch, importId: importId)
                        return
                    }

                    guard let costRaw = columnMap.value(at: columnMap.costIndex, in: fields),
                          let costMicros = ImportValueParsers.parseCostToMicros(costRaw) else {
                        invalidRows += 1
                        errorBatch.append(makeError(
                            importId: importId,
                            rowNumber: rowNumber,
                            severity: .error,
                            fieldName: "费用",
                            message: "无法解析费用",
                            rawValue: columnMap.value(at: columnMap.costIndex, in: fields)
                        ))
                        try await appendErrors(&errorBatch, importId: importId)
                        return
                    }

                    guard let impressionsRaw = columnMap.value(at: columnMap.impressionsIndex, in: fields),
                          let impressions = ImportValueParsers.parseInteger(impressionsRaw) else {
                        invalidRows += 1
                        errorBatch.append(makeError(
                            importId: importId,
                            rowNumber: rowNumber,
                            severity: .error,
                            fieldName: "展示次数",
                            message: "无法解析展示次数",
                            rawValue: columnMap.value(at: columnMap.impressionsIndex, in: fields)
                        ))
                        try await appendErrors(&errorBatch, importId: importId)
                        return
                    }

                    guard let clicksRaw = columnMap.value(at: columnMap.clicksIndex, in: fields),
                          let clicks = ImportValueParsers.parseInteger(clicksRaw) else {
                        invalidRows += 1
                        errorBatch.append(makeError(
                            importId: importId,
                            rowNumber: rowNumber,
                            severity: .error,
                            fieldName: "点击次数",
                            message: "无法解析点击次数",
                            rawValue: columnMap.value(at: columnMap.clicksIndex, in: fields)
                        ))
                        try await appendErrors(&errorBatch, importId: importId)
                        return
                    }

                    guard let conversionsRaw = columnMap.value(at: columnMap.conversionsIndex, in: fields),
                          let conversions = ImportValueParsers.parseDecimal(conversionsRaw) else {
                        invalidRows += 1
                        errorBatch.append(makeError(
                            importId: importId,
                            rowNumber: rowNumber,
                            severity: .error,
                            fieldName: "转化次数",
                            message: "无法解析转化次数",
                            rawValue: columnMap.value(at: columnMap.conversionsIndex, in: fields)
                        ))
                        try await appendErrors(&errorBatch, importId: importId)
                        return
                    }

                    guard let conversionValueRaw = columnMap.value(at: columnMap.conversionValueIndex, in: fields),
                          let conversionValueCents = ImportValueParsers.parseCurrencyToCents(conversionValueRaw) else {
                        invalidRows += 1
                        errorBatch.append(makeError(
                            importId: importId,
                            rowNumber: rowNumber,
                            severity: .error,
                            fieldName: "转化价值",
                            message: "无法解析转化价值",
                            rawValue: columnMap.value(at: columnMap.conversionValueIndex, in: fields)
                        ))
                        try await appendErrors(&errorBatch, importId: importId)
                        return
                    }

                    adsBatch.append(AdsProductDailyRecord(
                        date: isoDate,
                        itemId: itemId,
                        productId: normalized.productID,
                        variantId: normalized.variantID,
                        campaign: campaign,
                        currencyCode: currencyCode,
                        costMicros: costMicros,
                        impressions: impressions,
                        clicks: clicks,
                        conversions: conversions,
                        conversionValueCents: conversionValueCents,
                        importId: importId
                    ))
                    validRows += 1

                    if adsBatch.count >= batchSize {
                        try await flushBatch(&adsBatch)
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

            try await flushBatch(&adsBatch)
            try await appendErrors(&errorBatch, importId: importId, force: true)

            job.totalRows = processedRows
            job.validRows = validRows
            job.invalidRows = invalidRows
            job.warningRows = warningRows
            job.status = ImportJobStatus.succeeded.rawValue
            try await databaseClient.updateImportJob(job)

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
            try? await databaseClient.rollbackImport(importId: importId, sourceKind: .adsProduct)
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
            try? await databaseClient.rollbackImport(importId: importId, sourceKind: .adsProduct)
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

    private func flushBatch(_ batch: inout [AdsProductDailyRecord]) async throws {
        guard !batch.isEmpty else { return }
        try await databaseClient.insertAdsProductDailyBatch(batch)
        batch.removeAll(keepingCapacity: true)
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
