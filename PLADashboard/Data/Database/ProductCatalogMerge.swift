import Foundation

enum ProductCatalogMerge {
    static func pickBetterString(_ existing: String?, _ incoming: String?) -> String? {
        let existingTrimmed = existing?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let incomingTrimmed = incoming?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if existingTrimmed.isEmpty { return incomingTrimmed.isEmpty ? existing : incoming }
        if incomingTrimmed.isEmpty { return existing }
        return incomingTrimmed.count >= existingTrimmed.count ? incoming : existing
    }

    static func merge(into target: inout ProductRecord, from source: ProductRecord) {
        target.title = pickBetterString(target.title, source.title)
        target.canonicalLink = pickBetterString(target.canonicalLink, source.canonicalLink)
        target.imageUrl = pickBetterString(target.imageUrl, source.imageUrl)
        target.customLabel0 = pickBetterString(target.customLabel0, source.customLabel0)
        target.customLabel1 = pickBetterString(target.customLabel1, source.customLabel1)
        target.customLabel2 = pickBetterString(target.customLabel2, source.customLabel2)
        target.customLabel3 = pickBetterString(target.customLabel3, source.customLabel3)
        target.customLabel4 = pickBetterString(target.customLabel4, source.customLabel4)
        target.googleProductCategory = pickBetterString(
            target.googleProductCategory,
            source.googleProductCategory
        )

        if let sourceLSIN = source.lsin?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceLSIN.isEmpty {
            target.lsin = pickBetterString(target.lsin, sourceLSIN)
        } else if source.productId.first?.uppercased() == "S",
                  source.productId.dropFirst().allSatisfy(\.isNumber) {
            target.lsin = pickBetterString(target.lsin, source.productId)
        }

        if let sourceLastSeen = source.lastSeenAt {
            target.lastSeenAt = pickBetterString(target.lastSeenAt, sourceLastSeen)
        }
        target.updatedFromImportId = pickBetterString(target.updatedFromImportId, source.updatedFromImportId)
    }
}
