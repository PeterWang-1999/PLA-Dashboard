import Foundation

actor PlaDeliveryDetailImporter {
    /// 投放产品明细：第 1 行即表头，不跳过标题行。
    static let linesToSkip = 0

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
            sourceKind: ImportSourceKind.plaDeliveryDetail.rawValue,
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

        let format = ImportSpreadsheetFormat.detect(at: staging.stagedFileURL)

        await onProgress(ImportProgress(
            phase: .parsing,
            processedRows: 0,
            totalRowsEstimate: nil,
            validRows: 0,
            invalidRows: 0,
            warningRows: 0,
            message: "正在统计行数…"
        ))

        let state = ImportAccumulationState()

        if format == .delimited {
            let estimate = try DelimitedFileLineCounter.estimateDataRowCount(
                fileURL: staging.stagedFileURL,
                linesToSkip: Self.linesToSkip
            )
            state.estimatedTotalRows = estimate > 0 ? estimate : nil
            await onProgress(ImportProgress(
                phase: .parsing,
                processedRows: 0,
                totalRowsEstimate: state.estimatedTotalRows,
                validRows: 0,
                invalidRows: 0,
                warningRows: 0,
                message: "正在解析投放产品明细…"
            ))
        }

        do {
            try await consumeRows(
                format: format,
                stagedFileURL: staging.stagedFileURL,
                state: state,
                onProgress: onProgress
            ) { event in
                try await self.handleEvent(
                    event,
                    importId: importId,
                    state: state,
                    onProgress: onProgress
                )
            }

            guard state.columnMap != nil else {
                throw StreamingDelimitedParserError.missingHeader
            }

            try await flushBatch(state)
            try await flushFirstListedDates(state, importId: importId, importedAt: importedAt)
            try await flushPlaCMS3(state, importId: importId, importedAt: importedAt)
            try await appendErrors(state, force: true)

            job.totalRows = state.processedRows
            job.validRows = state.validRows
            job.invalidRows = state.invalidRows
            job.warningRows = state.warningRows
            job.status = ImportJobStatus.succeeded.rawValue
            try await databaseClient.updateImportJob(job)

            let errors = try await databaseClient.fetchImportErrors(importId: importId)
            return ImportResult(
                importId: importId,
                stagedFileURL: staging.stagedFileURL,
                job: job,
                errors: errors
            )
        } catch is CancellationError {
            try? await databaseClient.rollbackImport(importId: importId, sourceKind: .plaDeliveryDetail)
            try? await databaseClient.markImportCancelled(importId: importId)
            await onProgress(ImportProgress(
                phase: .cancelled,
                processedRows: state.processedRows,
                totalRowsEstimate: nil,
                validRows: state.validRows,
                invalidRows: state.invalidRows,
                warningRows: state.warningRows,
                message: "导入已取消"
            ))
            throw ImportPipelineError.cancelled
        } catch {
            try? await databaseClient.rollbackImport(importId: importId, sourceKind: .plaDeliveryDetail)
            await onProgress(ImportProgress(
                phase: .failed,
                processedRows: state.processedRows,
                totalRowsEstimate: nil,
                validRows: state.validRows,
                invalidRows: state.invalidRows,
                warningRows: state.warningRows,
                message: error.localizedDescription
            ))
            throw error
        }
    }

    private enum RowEvent: Sendable {
        case header([String])
        case row(rowNumber: Int, fields: [String])
    }

    private func consumeRows(
        format: ImportSpreadsheetFormat,
        stagedFileURL: URL,
        state: ImportAccumulationState,
        onProgress: @Sendable @escaping (ImportProgress) async -> Void,
        handler: @escaping @Sendable (RowEvent) async throws -> Void
    ) async throws {
        switch format {
        case .xlsx:
            let parser = StreamingXLSXRowParser(fileURL: stagedFileURL)
            try await parser.forEachEvent(
                onEstimate: { estimate in
                    state.estimatedTotalRows = estimate > 0 ? estimate : nil
                    await onProgress(ImportProgress(
                        phase: .parsing,
                        processedRows: 0,
                        totalRowsEstimate: state.estimatedTotalRows,
                        validRows: 0,
                        invalidRows: 0,
                        warningRows: 0,
                        message: "正在解析投放产品明细…"
                    ))
                },
                handler: { event in
                    switch event {
                    case .header(let headers):
                        try await handler(.header(headers))
                    case .row(let rowNumber, let fields):
                        try await handler(.row(rowNumber: rowNumber, fields: fields))
                    }
                }
            )
        case .delimited:
            let separator = try DelimitedFileSniffer.detectSeparator(
                fileURL: stagedFileURL,
                linesToSkip: Self.linesToSkip
            )
            let parser = StreamingDelimitedParser(
                fileURL: stagedFileURL,
                delimiter: separator,
                linesToSkip: Self.linesToSkip
            )
            try await parser.forEachEvent { event in
                switch event {
                case .header(let headers):
                    try await handler(.header(headers))
                case .row(let rowNumber, let fields):
                    try await handler(.row(rowNumber: rowNumber, fields: fields))
                }
            }
        }
    }

    private func handleEvent(
        _ event: RowEvent,
        importId: String,
        state: ImportAccumulationState,
        onProgress: @Sendable (ImportProgress) async -> Void
    ) async throws {
        try Task.checkCancellation()
        let estimatedTotalRows = state.estimatedTotalRows

        switch event {
        case .header(let headers):
            state.columnMap = try PlaDeliveryDetailColumnMap(headers: headers)
            await onProgress(ImportProgress(
                phase: .writing,
                processedRows: 0,
                totalRowsEstimate: estimatedTotalRows,
                validRows: 0,
                invalidRows: 0,
                warningRows: 0,
                message: nil
            ))

        case .row(let rowNumber, let fields):
            state.processedRows += 1
            guard let columnMap = state.columnMap else {
                throw StreamingDelimitedParserError.missingHeader
            }

            guard let lsinRaw = columnMap.value(at: columnMap.lsinIndex, in: fields) else {
                state.invalidRows += 1
                state.errorBatch.append(makeError(
                    importId: importId,
                    rowNumber: rowNumber,
                    severity: .error,
                    fieldName: "LSIN",
                    message: "LSIN 为空",
                    rawValue: nil
                ))
                try await appendErrors(state)
                return
            }

            let normalized = ProductIDNormalizer.normalizeLSIN(lsinRaw)
            guard !normalized.productID.isEmpty else {
                state.invalidRows += 1
                state.errorBatch.append(makeError(
                    importId: importId,
                    rowNumber: rowNumber,
                    severity: .error,
                    fieldName: "LSIN",
                    message: "无法解析 LSIN",
                    rawValue: lsinRaw
                ))
                try await appendErrors(state)
                return
            }

            if normalized.confidence == .medium {
                state.warningRows += 1
                state.errorBatch.append(makeError(
                    importId: importId,
                    rowNumber: rowNumber,
                    severity: .warning,
                    fieldName: "LSIN",
                    message: "LSIN 使用回退规则解析",
                    rawValue: lsinRaw
                ))
            }

            guard let dateRaw = columnMap.value(at: columnMap.dateIndex, in: fields),
                  let isoDate = ImportValueParsers.parseISODate(dateRaw) else {
                state.invalidRows += 1
                state.errorBatch.append(makeError(
                    importId: importId,
                    rowNumber: rowNumber,
                    severity: .error,
                    fieldName: "日期",
                    message: "无法解析日期",
                    rawValue: columnMap.value(at: columnMap.dateIndex, in: fields)
                ))
                try await appendErrors(state)
                return
            }

            guard let costRaw = columnMap.value(at: columnMap.marketCostIndex, in: fields),
                  let costMicros = ImportValueParsers.parseCostToMicros(costRaw) else {
                state.invalidRows += 1
                state.errorBatch.append(makeError(
                    importId: importId,
                    rowNumber: rowNumber,
                    severity: .error,
                    fieldName: "Market Cost",
                    message: "无法解析 Market Cost",
                    rawValue: columnMap.value(at: columnMap.marketCostIndex, in: fields)
                ))
                try await appendErrors(state)
                return
            }

            guard let impressionsRaw = columnMap.value(at: columnMap.impressionsIndex, in: fields),
                  let impressions = ImportValueParsers.parseCount(impressionsRaw) else {
                state.invalidRows += 1
                state.errorBatch.append(makeError(
                    importId: importId,
                    rowNumber: rowNumber,
                    severity: .error,
                    fieldName: "Impressions",
                    message: "无法解析 Impressions",
                    rawValue: columnMap.value(at: columnMap.impressionsIndex, in: fields)
                ))
                try await appendErrors(state)
                return
            }

            guard let clicksRaw = columnMap.value(at: columnMap.clicksIndex, in: fields),
                  let clicks = ImportValueParsers.parseCount(clicksRaw) else {
                state.invalidRows += 1
                state.errorBatch.append(makeError(
                    importId: importId,
                    rowNumber: rowNumber,
                    severity: .error,
                    fieldName: "Clicks",
                    message: "无法解析 Clicks",
                    rawValue: columnMap.value(at: columnMap.clicksIndex, in: fields)
                ))
                try await appendErrors(state)
                return
            }

            guard let conversionsRaw = columnMap.value(at: columnMap.conversionsIndex, in: fields),
                  let conversions = ImportValueParsers.parseDecimal(conversionsRaw) else {
                state.invalidRows += 1
                state.errorBatch.append(makeError(
                    importId: importId,
                    rowNumber: rowNumber,
                    severity: .error,
                    fieldName: "Conversions",
                    message: "无法解析 Conversions",
                    rawValue: columnMap.value(at: columnMap.conversionsIndex, in: fields)
                ))
                try await appendErrors(state)
                return
            }

            guard let conversionValueRaw = columnMap.value(
                at: columnMap.conversionValueIndex,
                in: fields
            ),
                  let conversionValueCents = ImportValueParsers.parseCurrencyToCents(
                    conversionValueRaw
                  ) else {
                state.invalidRows += 1
                state.errorBatch.append(makeError(
                    importId: importId,
                    rowNumber: rowNumber,
                    severity: .error,
                    fieldName: "Conversion Value",
                    message: "无法解析 Conversion Value",
                    rawValue: columnMap.value(at: columnMap.conversionValueIndex, in: fields)
                ))
                try await appendErrors(state)
                return
            }

            state.adsBatch.append(AdsProductDailyRecord(
                date: isoDate,
                itemId: lsinRaw,
                productId: normalized.productID,
                variantId: normalized.variantID,
                campaign: PlaDeliveryDetailColumnMap.placeholderCampaign,
                currencyCode: PlaDeliveryDetailColumnMap.placeholderCurrencyCode,
                costMicros: costMicros,
                impressions: impressions,
                clicks: clicks,
                conversions: conversions,
                conversionValueCents: conversionValueCents,
                importId: importId
            ))

            if let listedIndex = columnMap.firstListedAtIndex,
               let listedRaw = columnMap.value(at: listedIndex, in: fields),
               let listedDay = ImportValueParsers.parseISODate(listedRaw) {
                if let existing = state.firstListedByProductID[normalized.productID] {
                    if listedDay < existing {
                        state.firstListedByProductID[normalized.productID] = listedDay
                    }
                } else {
                    state.firstListedByProductID[normalized.productID] = listedDay
                }
            }

            if let cms3Index = columnMap.cms3Index,
               let cms3Raw = columnMap.value(at: cms3Index, in: fields) {
                let cms3 = cms3Raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cms3.isEmpty {
                    var byCMS3 = state.cms3CostMicrosByProductID[normalized.productID] ?? [:]
                    byCMS3[cms3, default: 0] += costMicros
                    state.cms3CostMicrosByProductID[normalized.productID] = byCMS3
                }
            }

            state.validRows += 1

            if state.adsBatch.count >= batchSize {
                try await flushBatch(state)
            }

            try await appendErrors(state)

            if state.processedRows.isMultiple(of: 100) {
                await onProgress(ImportProgress(
                    phase: .writing,
                    processedRows: state.processedRows,
                    totalRowsEstimate: state.estimatedTotalRows,
                    validRows: state.validRows,
                    invalidRows: state.invalidRows,
                    warningRows: state.warningRows,
                    message: nil
                ))
            }
        }
    }

    private func flushBatch(_ state: ImportAccumulationState) async throws {
        guard !state.adsBatch.isEmpty else { return }
        let batch = state.adsBatch
        state.adsBatch.removeAll(keepingCapacity: true)
        try await databaseClient.insertAdsProductDailyBatch(batch)
    }

    private func flushFirstListedDates(
        _ state: ImportAccumulationState,
        importId: String,
        importedAt: String
    ) async throws {
        guard !state.firstListedByProductID.isEmpty else { return }
        let entries = state.firstListedByProductID.map { (productId: $0.key, firstListedAt: $0.value) }
        state.firstListedByProductID.removeAll(keepingCapacity: true)
        try await databaseClient.upsertProductFirstListedAtBatch(
            entries,
            importId: importId,
            importedAt: importedAt
        )
    }

    private func flushPlaCMS3(
        _ state: ImportAccumulationState,
        importId: String,
        importedAt: String
    ) async throws {
        guard !state.cms3CostMicrosByProductID.isEmpty else { return }
        let entries: [(productId: String, plaCms3: String)] = state.cms3CostMicrosByProductID.compactMap { productId, costs in
            guard let best = costs.max(by: { $0.value < $1.value }) else { return nil }
            return (productId: productId, plaCms3: best.key)
        }
        state.cms3CostMicrosByProductID.removeAll(keepingCapacity: true)
        try await databaseClient.upsertProductPlaCMS3Batch(
            entries,
            importId: importId,
            importedAt: importedAt
        )
    }

    private func appendErrors(
        _ state: ImportAccumulationState,
        force: Bool = false
    ) async throws {
        guard force || state.errorBatch.count >= batchSize else { return }
        let batch = state.errorBatch
        state.errorBatch.removeAll(keepingCapacity: true)
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

/// 跨回调累积导入状态（由 Importer actor 串行访问）。
private final class ImportAccumulationState: @unchecked Sendable {
    var columnMap: PlaDeliveryDetailColumnMap?
    var estimatedTotalRows: Int?
    var adsBatch: [AdsProductDailyRecord] = []
    var errorBatch: [ImportRowErrorRecord] = []
    /// product_id → 本文件内最早的首次上架日（`yyyy-MM-dd`）。
    var firstListedByProductID: [String: String] = [:]
    /// product_id → CMS3 → 本文件累计花费（micros），用于选主类目。
    var cms3CostMicrosByProductID: [String: [String: Int]] = [:]
    var processedRows = 0
    var validRows = 0
    var invalidRows = 0
    var warningRows = 0
}

enum ImportSpreadsheetFormat: Sendable {
    case xlsx
    case delimited

    static func detect(at fileURL: URL) -> ImportSpreadsheetFormat {
        if isBinarySpreadsheet(at: fileURL) {
            return .xlsx
        }
        return .delimited
    }

    static func isBinarySpreadsheet(at fileURL: URL) -> Bool {
        let ext = fileURL.pathExtension.lowercased()
        if ext == "xlsx" || ext == "xls" {
            return true
        }
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return false }
        defer { try? handle.close() }
        guard let preview = try? handle.read(upToCount: 4), preview.count >= 4 else {
            return false
        }
        return preview[0] == 0x50
            && preview[1] == 0x4B
            && preview[2] == 0x03
            && preview[3] == 0x04
    }
}
