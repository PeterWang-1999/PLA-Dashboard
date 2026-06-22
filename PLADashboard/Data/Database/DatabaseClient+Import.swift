import Foundation
import GRDB

extension DatabaseClient {
    static let currentImportSchemaVersion = 1

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
        try dbQueue.write { db in
            for item in items {
                try item.insert(db, onConflict: .replace)
            }
        }
    }

    // MARK: - Products

    func upsertProductsBatch(_ candidates: [ProductRecord], importId: String, importedAt: String) throws {
        guard !candidates.isEmpty else { return }
        try dbQueue.write { db in
            for candidate in candidates {
                if var existing = try ProductRecord.fetchOne(db, key: candidate.productId) {
                    if shouldReplaceProduct(existing: existing, incoming: candidate, importId: importId) {
                        existing.title = pickBetterString(existing.title, candidate.title)
                        existing.canonicalLink = pickBetterString(existing.canonicalLink, candidate.canonicalLink)
                        existing.imageUrl = pickBetterString(existing.imageUrl, candidate.imageUrl)
                        existing.customLabel0 = pickBetterString(existing.customLabel0, candidate.customLabel0)
                        existing.customLabel1 = pickBetterString(existing.customLabel1, candidate.customLabel1)
                        existing.customLabel2 = pickBetterString(existing.customLabel2, candidate.customLabel2)
                        existing.customLabel3 = pickBetterString(existing.customLabel3, candidate.customLabel3)
                        existing.customLabel4 = pickBetterString(existing.customLabel4, candidate.customLabel4)
                        existing.lastSeenAt = importedAt
                        existing.updatedFromImportId = importId
                        try existing.update(db)
                    } else {
                        existing.lastSeenAt = importedAt
                        try existing.update(db)
                    }
                } else {
                    var newProduct = candidate
                    newProduct.firstSeenAt = importedAt
                    newProduct.lastSeenAt = importedAt
                    newProduct.updatedFromImportId = importId
                    try newProduct.insert(db)
                }
            }
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

    private func pickBetterString(_ existing: String?, _ incoming: String?) -> String? {
        let existingTrimmed = existing?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let incomingTrimmed = incoming?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if existingTrimmed.isEmpty { return incomingTrimmed.isEmpty ? existing : incoming }
        if incomingTrimmed.isEmpty { return existing }
        return incomingTrimmed.count >= existingTrimmed.count ? incoming : existing
    }

    // MARK: - Import errors

    func insertImportErrorsBatch(_ errors: [ImportRowErrorRecord]) throws {
        guard !errors.isEmpty else { return }
        try dbQueue.write { db in
            for error in errors {
                try error.insert(db)
            }
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

    // MARK: - FTS

    func replaceProductSearchEntries(_ products: [ProductRecord]) throws {
        guard !products.isEmpty else { return }
        try dbQueue.write { db in
            for product in products {
                try db.execute(
                    sql: "DELETE FROM product_search WHERE product_id = ?;",
                    arguments: [product.productId]
                )
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
        }
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

    func rollbackImport(importId: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM merchant_items WHERE import_id = ?;",
                arguments: [importId]
            )
            try db.execute(
                sql: "DELETE FROM import_row_errors WHERE import_id = ?;",
                arguments: [importId]
            )
            if var job = try ImportJobRecord.fetchOne(db, key: importId) {
                job.status = ImportJobStatus.failed.rawValue
                try job.update(db)
            }
        }
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
