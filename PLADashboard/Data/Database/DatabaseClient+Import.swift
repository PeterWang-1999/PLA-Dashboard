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
            if job.status == ImportJobStatus.succeeded.rawValue {
                try markWeeklyMetricsDirty(for: job, db: db)
            }
        }
    }

    func finishProductDetailImport(
        _ job: ImportJobRecord,
        firstListedDates: [(productId: String, firstListedAt: String)],
        categories: [(productId: String, category: PlaProductCategory)],
        productTags: [String: PlaProductTagSnapshot],
        replacingExisting: Bool
    ) throws {
        try dbQueue.write { db in
            if replacingExisting { try discardUnchangedAds(for: job, db: db) }
            try job.update(db)
            try markWeeklyMetricsDirty(for: job, db: db)
            if replacingExisting {
                try db.execute(sql: """
                    DELETE FROM ads_product_daily WHERE rowid IN (
                      SELECT old.rowid FROM ads_product_daily n
                      CROSS JOIN ads_product_daily old ON old.date = n.date AND old.item_id = n.item_id
                        AND old.campaign = n.campaign AND old.currency_code = n.currency_code
                      JOIN import_jobs j ON j.id = old.import_id
                      WHERE n.import_id = ? AND old.import_id != n.import_id AND j.status = ?
                    );
                    """, arguments: [job.id, ImportJobStatus.succeeded.rawValue])
            }
            try upsertProductFirstListedDates(firstListedDates, importId: job.id, importedAt: job.importedAt, db: db)
            try upsertProductPlaCategories(categories, importId: job.id, importedAt: job.importedAt, db: db)
            try updatePlaProductTags(productTags, db: db)
        }
        invalidateDashboardCache()
    }

    private func updatePlaProductTags(_ snapshots: [String: PlaProductTagSnapshot], db: Database) throws {
        guard !snapshots.isEmpty else { return }
        let saveDay = try db.makeStatement(sql: """
            INSERT INTO pla_product_tag_snapshots (product_id, report_day) VALUES (?, ?)
            ON CONFLICT(product_id) DO UPDATE SET report_day = excluded.report_day
            WHERE excluded.report_day >= pla_product_tag_snapshots.report_day;
            """)
        let removeTags = try db.makeStatement(sql: "DELETE FROM pla_product_tags WHERE product_id = ?;")
        let insertTag = try db.makeStatement(sql: "INSERT INTO pla_product_tags (product_id, tag) VALUES (?, ?);")
        for (productID, snapshot) in snapshots {
            try saveDay.execute(arguments: [productID, snapshot.reportDay])
            guard db.changesCount > 0 else { continue }
            try removeTags.execute(arguments: [productID])
            for tag in snapshot.tags {
                try insertTag.execute(arguments: [productID, tag])
            }
        }
    }

    private func discardUnchangedAds(for job: ImportJobRecord, db: Database) throws {
        try db.execute(sql: """
            DELETE FROM ads_product_daily AS n
            WHERE n.import_id = ? AND EXISTS (
              SELECT 1 FROM ads_product_daily old
              WHERE old.rowid = (
                SELECT a.rowid FROM ads_product_daily a
                JOIN import_jobs j ON j.id = a.import_id
                WHERE a.date = n.date AND a.item_id = n.item_id
                  AND a.campaign = n.campaign AND a.currency_code = n.currency_code
                  AND j.status = ?
                ORDER BY j.imported_at DESC, a.rowid DESC LIMIT 1
              )
              AND old.product_id = n.product_id AND old.variant_id IS n.variant_id
              AND old.cost_micros = n.cost_micros AND old.impressions = n.impressions
              AND old.clicks = n.clicks AND old.conversions = n.conversions
              AND old.conversion_value_cents = n.conversion_value_cents
            );
            """, arguments: [job.id, ImportJobStatus.succeeded.rawValue])
    }

    private func markWeeklyMetricsDirty(for job: ImportJobRecord, db: Database) throws {
        guard try db.tableExists("weekly_metrics_dirty_products") else { return }
        // 包含同一自然键的历史产品：ID 改变时旧产品也必须清除旧指标。
        switch ImportSourceKind(rawValue: job.sourceKind) {
        case .adsProduct, .plaDeliveryDetail:
            try db.execute(sql: """
                INSERT OR IGNORE INTO weekly_metrics_dirty_products (product_id)
                SELECT a.product_id FROM ads_product_daily n
                JOIN ads_product_daily a
                  ON a.date = n.date AND a.item_id = n.item_id
                 AND a.campaign = n.campaign AND a.currency_code = n.currency_code
                WHERE n.import_id = ?;
                """, arguments: [job.id])
        case .salesReport:
            try db.execute(sql: """
                INSERT OR IGNORE INTO weekly_metrics_dirty_products (product_id)
                SELECT s.product_id FROM sales_daily n
                JOIN sales_daily s ON s.date = n.date AND s.lsin = n.lsin
                WHERE n.import_id = ? AND s.product_id IS NOT NULL
                  AND TRIM(s.product_id) != '';
                """, arguments: [job.id])
        case .merchantCenter, .none:
            break
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
                    existing.imageUrl = ProductCatalogMerge.pickBetterImageURL(existing.imageUrl, candidate.imageUrl)
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
            try db.bulkInsertSalesDaily(rows)
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

    /// 诊断：销售日表 / 周表的 GS、毛利覆盖（供 E2E 对照 Python）。
    func salesGrossProfitCoverage(weekStarts: [String]) throws -> (
        salesRowsWithGS: Int,
        salesRowsWithGP: Int,
        salesProductsWithGS: Int,
        salesProductsWithGP: Int,
        weeklyProductsWithGS: Int,
        weeklyProductsWithGP: Int,
        salesProfitSumCents: Int,
        salesGrossSumCents: Int
    ) {
        try dbQueue.read { db in
            let salesRowsWithGS = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM sales_daily WHERE gross_sales_cents > 0;
                """) ?? 0
            let salesRowsWithGP = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM sales_daily WHERE gross_profit_cents > 0;
                """) ?? 0
            let salesProductsWithGS = try Int.fetchOne(db, sql: """
                SELECT COUNT(DISTINCT product_id) FROM sales_daily
                WHERE gross_sales_cents > 0 AND product_id IS NOT NULL AND TRIM(product_id) != '';
                """) ?? 0
            let salesProductsWithGP = try Int.fetchOne(db, sql: """
                SELECT COUNT(DISTINCT product_id) FROM sales_daily
                WHERE gross_profit_cents > 0 AND product_id IS NOT NULL AND TRIM(product_id) != '';
                """) ?? 0
            let sums = try Row.fetchOne(db, sql: """
                SELECT
                  COALESCE(SUM(gross_sales_cents), 0) AS gs,
                  COALESCE(SUM(gross_profit_cents), 0) AS gp
                FROM sales_daily;
                """)
            let salesGrossSumCents: Int = sums?["gs"] ?? 0
            let salesProfitSumCents: Int = sums?["gp"] ?? 0

            guard !weekStarts.isEmpty else {
                return (
                    salesRowsWithGS, salesRowsWithGP,
                    salesProductsWithGS, salesProductsWithGP,
                    0, 0, salesProfitSumCents, salesGrossSumCents
                )
            }
            let placeholders = Array(repeating: "?", count: weekStarts.count).joined(separator: ", ")
            var args = StatementArguments()
            for week in weekStarts { args += [week] }
            let weeklyProductsWithGS = try Int.fetchOne(db, sql: """
                SELECT COUNT(DISTINCT product_id) FROM product_weekly_metrics
                WHERE week_start IN (\(placeholders)) AND gross_sales_cents > 0;
                """, arguments: args) ?? 0
            var args2 = StatementArguments()
            for week in weekStarts { args2 += [week] }
            let weeklyProductsWithGP = try Int.fetchOne(db, sql: """
                SELECT COUNT(DISTINCT product_id) FROM product_weekly_metrics
                WHERE week_start IN (\(placeholders)) AND gross_profit_cents > 0;
                """, arguments: args2) ?? 0

            return (
                salesRowsWithGS, salesRowsWithGP,
                salesProductsWithGS, salesProductsWithGP,
                weeklyProductsWithGS, weeklyProductsWithGP,
                salesProfitSumCents, salesGrossSumCents
            )
        }
    }

    // MARK: - Ads product daily

    func insertAdsProductDailyBatch(_ rows: [AdsProductDailyRecord], accumulatingMetrics: Bool = false) throws {
        guard !rows.isEmpty else { return }
        let signpost = PerformanceSignposts.beginImportFlush()
        defer { PerformanceSignposts.endImportFlush(signpost) }
        try dbQueue.write { db in
            try db.bulkInsertAdsProductDaily(rows, accumulatingMetrics: accumulatingMetrics)
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
                        firstListedAt: nil,
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

    /// 写入投放明细中的首次上架日：保留更早的日期；不存在的产品则创建占位行。
    private func upsertProductFirstListedDates(
        _ entries: [(productId: String, firstListedAt: String)],
        importId: String,
        importedAt: String,
        db: Database
    ) throws {
        guard !entries.isEmpty else { return }
        let ids = entries.map(\.productId)
        let existingRows = try ProductRecord
            .filter(ids.contains(ProductRecord.Columns.productId))
            .fetchAll(db)
        var existingByID = Dictionary(uniqueKeysWithValues: existingRows.map { ($0.productId, $0) })

        var toInsert: [ProductRecord] = []
        var toUpdate: [ProductRecord] = []

        for entry in entries {
            if var existing = existingByID[entry.productId] {
                if let current = existing.firstListedAt,
                   !current.isEmpty,
                   current <= entry.firstListedAt {
                    continue
                }
                existing.firstListedAt = entry.firstListedAt
                existing.lastSeenAt = importedAt
                existing.updatedFromImportId = importId
                toUpdate.append(existing)
                existingByID[entry.productId] = existing
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
                    lsin: nil,
                    googleProductCategory: nil,
                    firstListedAt: entry.firstListedAt,
                    firstSeenAt: importedAt,
                    lastSeenAt: importedAt,
                    updatedFromImportId: importId
                )
                toInsert.append(product)
                existingByID[entry.productId] = product
            }
        }

        if !toInsert.isEmpty {
            try db.insertRecords(toInsert)
        }
        for product in toUpdate {
            try product.update(db)
        }
    }

    /// 写入投放明细的主类目路径及 CMS3。
    private func upsertProductPlaCategories(
        _ entries: [(productId: String, category: PlaProductCategory)],
        importId: String,
        importedAt: String,
        db: Database
    ) throws {
        let statement = try db.makeStatement(sql: """
            INSERT INTO products (product_id, pla_category_path, pla_cms3, first_seen_at, last_seen_at, updated_from_import_id)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(product_id) DO UPDATE SET
                pla_category_path = excluded.pla_category_path,
                pla_cms3 = excluded.pla_cms3,
                last_seen_at = excluded.last_seen_at,
                updated_from_import_id = excluded.updated_from_import_id
            WHERE (excluded.pla_category_path IS NOT NULL OR products.pla_category_path IS NULL)
              AND (products.pla_category_path IS NOT excluded.pla_category_path OR products.pla_cms3 IS NOT excluded.pla_cms3);
            """)
        for (productID, category) in entries {
            try statement.execute(arguments: [productID, category.path, category.cms3, importedAt, importedAt, importId])
        }
    }

    /// 孤儿产品对账（幂等，顺序无关）：
    /// ① 为「有投放/销售数据但无 products 行」的产品建占位行并标记 GMC 缺失；
    /// ② 标记所有「无 merchant_items 行」的投放产品为 GMC 缺失；
    /// ③ 清除已回归目录产品的标记（自愈）。
    func reconcileOrphanProducts() throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO products (product_id, missing_in_gmc)
                SELECT m.product_id, 1
                FROM product_weekly_metrics m
                WHERE (m.cost_cents > 0 OR m.conversion_value_cents > 0)
                  AND NOT EXISTS (SELECT 1 FROM products p WHERE p.product_id = m.product_id)
                GROUP BY m.product_id;
                """)

            try db.execute(sql: """
                UPDATE products
                SET missing_in_gmc = 1
                WHERE product_id IN (
                  SELECT m.product_id
                  FROM product_weekly_metrics m
                  WHERE (m.cost_cents > 0 OR m.conversion_value_cents > 0)
                  GROUP BY m.product_id
                )
                AND product_id NOT IN (
                  SELECT DISTINCT product_id FROM merchant_items
                  WHERE product_id IS NOT NULL AND TRIM(product_id) != ''
                );
                """)

            try db.execute(sql: """
                UPDATE products
                SET missing_in_gmc = 0
                WHERE missing_in_gmc = 1
                  AND product_id IN (
                    SELECT DISTINCT product_id FROM merchant_items
                    WHERE product_id IS NOT NULL AND TRIM(product_id) != ''
                  );
                """)
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
        let plaCategories: [PlaCategoryNode]
        let productTags: [String]
        let customLabelCatalog: CustomLabelCatalog
    }

    func buildFilterCatalogSnapshot(accountKind: WorkspaceAccountKind = .thirdParty) throws -> FilterCatalogSnapshot {
        let categoryCatalog = accountKind == .selfBuilt ? .empty :
            GoogleProductCategoryCatalog.build(fromCategoryPaths: try fetchDistinctGoogleProductCategories())
        let plaCategories = accountKind == .selfBuilt ? try dbQueue.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT pla_category_path FROM products
                WHERE pla_category_path IS NOT NULL AND pla_category_path != '';
                """)
        } : []
        let customLabelValues = try fetchDistinctCustomLabelValues()
        let productTags = accountKind == .selfBuilt ? try dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT DISTINCT tag FROM pla_product_tags ORDER BY tag;")
        } : []
        return FilterCatalogSnapshot(
            categoryCatalog: categoryCatalog,
            plaCategories: PlaCategoryNode.tree(from: plaCategories),
            productTags: productTags,
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
            case .adsProduct, .plaDeliveryDetail:
                try db.execute(
                    sql: "DELETE FROM ads_product_daily WHERE import_id = ?;",
                    arguments: [importId]
                )
            }
            try db.execute(
                sql: "DELETE FROM import_row_errors WHERE import_id = ?;",
                arguments: [importId]
            )
            if try db.tableExists("weekly_metrics_refresh_state") {
                try db.execute(sql: "UPDATE weekly_metrics_refresh_state SET initialized = 0 WHERE id = 1;")
            }
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
