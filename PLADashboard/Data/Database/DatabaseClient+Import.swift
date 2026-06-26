import Foundation
import GRDB

extension DatabaseClient {
    static let currentImportSchemaVersion = 2

    // MARK: - Import jobs

    func createImportJob(_ job: ImportJobRecord) throws {
        try dbQueue.write { db in
            try job.insert(db)
        }
    }

    func updateImportJob(_ job: ImportJobRecord) throws {
        try dbQueue.write { db in
            try job.update(db)
        }
    }

    func fetchImportJob(id: String) throws -> ImportJobRecord? {
        try dbQueue.read { db in
            try ImportJobRecord.fetchOne(db, key: id)
        }
    }

    func fetchImportJobs(limit: Int = 50) throws -> [ImportJobRecord] {
        try dbQueue.read { db in
            try ImportJobRecord
                .order(ImportJobRecord.Columns.importedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func findImportJobByChecksum(_ checksum: String) throws -> ImportJobRecord? {
        try dbQueue.read { db in
            try ImportJobRecord
                .filter(ImportJobRecord.Columns.fileChecksum == checksum)
                .filter(ImportJobRecord.Columns.status == ImportJobStatus.succeeded.rawValue)
                .fetchOne(db)
        }
    }

    // MARK: - Merchant items

    func insertMerchantItemsBatch(_ items: [MerchantItemRecord]) throws {
        guard !items.isEmpty else { return }
        let signpost = PerformanceSignposts.beginImportFlush()
        defer { PerformanceSignposts.endImportFlush(signpost) }
        try dbQueue.write { db in
            try db.insertRecords(items, onConflict: .replace)
        }
        invalidateDashboardCache()
    }

    /// Merchant 导入批次：单次事务写入 merchant_items + products。
    func flushMerchantImportBatch(
        merchantItems: [MerchantItemRecord],
        productCandidates: [ProductRecord],
        importId: String,
        importedAt: String
    ) throws {
        guard !merchantItems.isEmpty else { return }
        let signpost = PerformanceSignposts.beginImportFlush()
        defer { PerformanceSignposts.endImportFlush(signpost) }
        try dbQueue.write { db in
            try db.insertRecords(merchantItems, onConflict: .replace)
            try upsertProductsInDatabase(
                db,
                candidates: productCandidates,
                importId: importId,
                importedAt: importedAt
            )
        }
        invalidateDashboardCache()
    }

    // MARK: - Products

    func upsertProductsBatch(_ candidates: [ProductRecord], importId: String, importedAt: String) throws {
        guard !candidates.isEmpty else { return }
        let signpost = PerformanceSignposts.beginImportFlush()
        defer { PerformanceSignposts.endImportFlush(signpost) }
        try dbQueue.write { db in
            try upsertProductsInDatabase(
                db,
                candidates: candidates,
                importId: importId,
                importedAt: importedAt
            )
        }
        invalidateDashboardCache()
    }

    private func upsertProductsInDatabase(
        _ db: Database,
        candidates: [ProductRecord],
        importId: String,
        importedAt: String
    ) throws {
        let ids = candidates.map(\.productId)
        let existingRows = try ProductRecord
            .filter(ids.contains(ProductRecord.Columns.productId))
            .fetchAll(db)
        let existingByID = Dictionary(uniqueKeysWithValues: existingRows.map { ($0.productId, $0) })

        var toInsert: [ProductRecord] = []
        var toUpdate: [ProductRecord] = []

        for candidate in candidates {
            if var existing = existingByID[candidate.productId] {
                if shouldReplaceProduct(existing: existing, incoming: candidate, importId: importId) {
                    existing.title = ProductCatalogMerge.pickBetterString(existing.title, candidate.title)
                    existing.canonicalLink = ProductCatalogMerge.pickBetterString(existing.canonicalLink, candidate.canonicalLink)
                    existing.imageUrl = ProductCatalogMerge.pickBetterString(existing.imageUrl, candidate.imageUrl)
                    existing.customLabel0 = ProductCatalogMerge.pickBetterString(existing.customLabel0, candidate.customLabel0)
                    existing.customLabel1 = ProductCatalogMerge.pickBetterString(existing.customLabel1, candidate.customLabel1)
                    existing.customLabel2 = ProductCatalogMerge.pickBetterString(existing.customLabel2, candidate.customLabel2)
                    existing.customLabel3 = ProductCatalogMerge.pickBetterString(existing.customLabel3, candidate.customLabel3)
                    existing.customLabel4 = ProductCatalogMerge.pickBetterString(existing.customLabel4, candidate.customLabel4)
                    existing.googleProductCategory = ProductCatalogMerge.pickBetterString(
                        existing.googleProductCategory,
                        normalizedCategory(from: candidate)
                    )
                    existing.lastSeenAt = importedAt
                    existing.updatedFromImportId = importId
                } else {
                    existing.lastSeenAt = importedAt
                }
                if let incomingCategory = normalizedCategory(from: candidate) {
                    existing.googleProductCategory = ProductCatalogMerge.pickBetterString(
                        existing.googleProductCategory,
                        incomingCategory
                    )
                }
                toUpdate.append(existing)
            } else {
                var newProduct = candidate
                newProduct.firstSeenAt = importedAt
                newProduct.lastSeenAt = importedAt
                newProduct.updatedFromImportId = importId
                toInsert.append(newProduct)
            }
        }

        if !toInsert.isEmpty {
            try db.insertRecords(toInsert)
        }
        for product in toUpdate {
            try product.update(db)
        }
    }

    private func shouldReplaceProduct(existing: ProductRecord, incoming: ProductRecord, importId: String) -> Bool {
        let existingScore = existing.completenessScore()
        let incomingScore = incoming.completenessScore()
        if incomingScore != existingScore {
            return incomingScore > existingScore
        }
        if existing.updatedFromImportId == importId {
            return true
        }
        return false
    }

    private func normalizedCategory(from candidate: ProductRecord) -> String? {
        guard let raw = candidate.googleProductCategory?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        if raw.range(of: #" c\d+_"#, options: .regularExpression) != nil {
            return ProductCategoryPath.normalizedForStorage(raw, accountKind: .selfBuilt) ?? raw
        }
        return raw
    }

    // MARK: - Sales daily

    func insertSalesDailyBatch(_ rows: [SalesDailyRecord]) throws {
        guard !rows.isEmpty else { return }
        let signpost = PerformanceSignposts.beginImportFlush()
        defer { PerformanceSignposts.endImportFlush(signpost) }
        try dbQueue.write { db in
            try db.insertRecords(rows, onConflict: .replace)
        }
        invalidateDashboardCache()
    }

    func countSalesDaily(importId: String) throws -> Int {
        try dbQueue.read { db in
            try SalesDailyRecord
                .filter(SalesDailyRecord.Columns.importId == importId)
                .fetchCount(db)
        }
    }

    // MARK: - Ads product daily

    func insertAdsProductDailyBatch(_ rows: [AdsProductDailyRecord]) throws {
        guard !rows.isEmpty else { return }
        let signpost = PerformanceSignposts.beginImportFlush()
        defer { PerformanceSignposts.endImportFlush(signpost) }
        try dbQueue.write { db in
            try db.bulkInsertAdsProductDaily(rows)
        }
        invalidateDashboardCache()
    }

    func countAdsProductDaily(importId: String) throws -> Int {
        try dbQueue.read { db in
            try AdsProductDailyRecord
                .filter(AdsProductDailyRecord.Columns.importId == importId)
                .fetchCount(db)
        }
    }

    func fetchAdsProductDaily(importId: String, limit: Int = 10) throws -> [AdsProductDailyRecord] {
        try dbQueue.read { db in
            try AdsProductDailyRecord
                .filter(AdsProductDailyRecord.Columns.importId == importId)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Product LSIN

    func upsertProductLSINBatch(
        _ entries: [(productId: String, lsin: String)],
        importId: String,
        importedAt: String
    ) throws {
        guard !entries.isEmpty else { return }
        let signpost = PerformanceSignposts.beginImportFlush()
        defer { PerformanceSignposts.endImportFlush(signpost) }
        try dbQueue.write { db in
            let ids = entries.map(\.productId)
            let existingRows = try ProductRecord
                .filter(ids.contains(ProductRecord.Columns.productId))
                .fetchAll(db)
            let existingByID = Dictionary(uniqueKeysWithValues: existingRows.map { ($0.productId, $0) })

            var toInsert: [ProductRecord] = []
            var toUpdate: [ProductRecord] = []

            for entry in entries {
                if var existing = existingByID[entry.productId] {
                    existing.lsin = entry.lsin
                    existing.lastSeenAt = importedAt
                    existing.updatedFromImportId = importId
                    toUpdate.append(existing)
                } else {
                    let product = ProductRecord(
                        productId: entry.productId,
                        title: nil,
                        canonicalLink: nil,
                        imageUrl: nil,
                        customLabel0: nil,
                        customLabel1: nil,
                        customLabel2: nil,
                        customLabel3: nil,
                        customLabel4: nil,
                        lsin: entry.lsin,
                        googleProductCategory: nil,
                        firstSeenAt: importedAt,
                        lastSeenAt: importedAt,
                        updatedFromImportId: importId
                    )
                    toInsert.append(product)
                }
            }

            if !toInsert.isEmpty {
                try db.insertRecords(toInsert)
            }
            for product in toUpdate {
                try product.update(db)
            }
        }
        invalidateDashboardCache()
    }

    // MARK: - Import errors

    func insertImportErrorsBatch(_ errors: [ImportRowErrorRecord]) throws {
        guard !errors.isEmpty else { return }
        try dbQueue.write { db in
            try db.insertRecords(errors)
        }
    }

    func fetchImportErrors(importId: String, limit: Int = 200) throws -> [ImportRowErrorRecord] {
        try dbQueue.read { db in
            try ImportRowErrorRecord
                .filter(ImportRowErrorRecord.Columns.importId == importId)
                .order(ImportRowErrorRecord.Columns.rowNumber.asc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Filter catalogs

    struct FilterCatalogSnapshot: Sendable {
        let categoryCatalog: GoogleProductCategoryCatalog
        let customLabelCatalog: CustomLabelCatalog
    }

    func buildFilterCatalogSnapshot() throws -> FilterCatalogSnapshot {
        let categoryPaths = try fetchDistinctGoogleProductCategories()
        let customLabelValues = try fetchDistinctCustomLabelValues()
        return FilterCatalogSnapshot(
            categoryCatalog: GoogleProductCategoryCatalog.build(fromCategoryPaths: categoryPaths),
            customLabelCatalog: CustomLabelCatalog.build(valuesByColumn: customLabelValues)
        )
    }

    func countProductsWithCategory() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*)
                FROM products
                WHERE google_product_category IS NOT NULL
                  AND TRIM(google_product_category) != '';
                """
            ) ?? 0
        }
    }

    func updateProductCategoriesBatch(_ updates: [(productId: String, category: String)]) throws -> Int {
        guard !updates.isEmpty else { return 0 }
        var applied = 0
        try dbQueue.write { db in
            for (productId, category) in updates {
                try db.execute(
                    sql: """
                    UPDATE products
                    SET google_product_category = ?
                    WHERE product_id = ?;
                    """,
                    arguments: [category, productId]
                )
                applied += db.changesCount
            }
        }
        invalidateDashboardCache()
        return applied
    }

    private func fetchDistinctGoogleProductCategories() throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: """
                SELECT DISTINCT google_product_category
                FROM products
                WHERE google_product_category IS NOT NULL
                  AND TRIM(google_product_category) != '';
                """
            )
        }
    }

    private func fetchDistinctCustomLabelValues() throws -> [String: [String]] {
        let columnNames = CustomLabelCatalog.columnNames
        let sqlColumns = [
            "custom_label_0",
            "custom_label_1",
            "custom_label_2",
            "custom_label_3",
            "custom_label_4",
        ]

        return try dbQueue.read { db in
            var valuesByColumn: [String: [String]] = [:]
            valuesByColumn.reserveCapacity(columnNames.count)

            for (columnName, sqlColumn) in zip(columnNames, sqlColumns) {
                let values = try String.fetchAll(
                    db,
                    sql: """
                    SELECT DISTINCT \(sqlColumn)
                    FROM products
                    WHERE \(sqlColumn) IS NOT NULL
                      AND TRIM(\(sqlColumn)) != '';
                    """
                )
                valuesByColumn[columnName] = values
            }
            return valuesByColumn
        }
    }

    // MARK: - FTS

    func replaceProductSearchEntries(_ products: [ProductRecord]) throws {
        guard !products.isEmpty else { return }
        try dbQueue.write { db in
            for product in products {
                try db.execute(
                    sql: "DELETE FROM product_search WHERE product_id = ?;",
                    arguments: [product.productId]
                )
                try insertProductSearchRow(db, product: product)
            }
        }
    }

    /// 全量重建 FTS 索引（Merchant 导入结束后调用）。
    func rebuildAllProductSearchIndex() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM product_search;")
            try db.execute(sql: """
                INSERT INTO product_search (
                  product_id, title, canonical_link,
                  custom_label_0, custom_label_1, custom_label_2,
                  custom_label_3, custom_label_4
                )
                SELECT
                  product_id, title, canonical_link,
                  custom_label_0, custom_label_1, custom_label_2,
                  custom_label_3, custom_label_4
                FROM products;
                """)
        }
    }

    private func insertProductSearchRow(_ db: Database, product: ProductRecord) throws {
        try db.execute(
            sql: """
                INSERT INTO product_search (
                  product_id, title, canonical_link,
                  custom_label_0, custom_label_1, custom_label_2,
                  custom_label_3, custom_label_4
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                """,
            arguments: [
                product.productId,
                product.title,
                product.canonicalLink,
                product.customLabel0,
                product.customLabel1,
                product.customLabel2,
                product.customLabel3,
                product.customLabel4,
            ]
        )
    }

    func fetchProducts(ids: [String]) throws -> [ProductRecord] {
        guard !ids.isEmpty else { return [] }
        return try dbQueue.read { db in
            try ProductRecord
                .filter(ids.contains(ProductRecord.Columns.productId))
                .fetchAll(db)
        }
    }

    // MARK: - Rollback

    func rollbackImport(importId: String, sourceKind: ImportSourceKind) throws {
        try dbQueue.write { db in
            switch sourceKind {
            case .merchantCenter:
                try db.execute(
                    sql: "DELETE FROM merchant_items WHERE import_id = ?;",
                    arguments: [importId]
                )
            case .salesReport:
                try db.execute(
                    sql: "DELETE FROM sales_daily WHERE import_id = ?;",
                    arguments: [importId]
                )
            case .adsProduct:
                try db.execute(
                    sql: "DELETE FROM ads_product_daily WHERE import_id = ?;",
                    arguments: [importId]
                )
            }
            try db.execute(
                sql: "DELETE FROM import_row_errors WHERE import_id = ?;",
                arguments: [importId]
            )
            if var job = try ImportJobRecord.fetchOne(db, key: importId) {
                job.status = ImportJobStatus.failed.rawValue
                try job.update(db)
            }
        }
        invalidateDashboardCache()
    }

    func rollbackImport(importId: String) throws {
        let sourceKindRaw = try dbQueue.read { db in
            try ImportJobRecord.fetchOne(db, key: importId)?.sourceKind
        }
        guard let sourceKindRaw,
              let sourceKind = ImportSourceKind(rawValue: sourceKindRaw) else {
            return
        }
        try rollbackImport(importId: importId, sourceKind: sourceKind)
    }

    func markImportCancelled(importId: String) throws {
        try dbQueue.write { db in
            if var job = try ImportJobRecord.fetchOne(db, key: importId) {
                job.status = ImportJobStatus.cancelled.rawValue
                try job.update(db)
            }
        }
    }

    func fetchDistinctProductIds(importId: String) throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT product_id
                    FROM merchant_items
                    WHERE import_id = ?;
                    """,
                arguments: [importId]
            )
        }
    }
}
