import Foundation

enum ProductCatalogMerge {
    static func pickBetterString(_ existing: String?, _ incoming: String?) -> String? {
        let existingTrimmed = existing?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let incomingTrimmed = incoming?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if existingTrimmed.isEmpty { return incomingTrimmed.isEmpty ? existing : incoming }
        if incomingTrimmed.isEmpty { return existing }
        return incomingTrimmed.count >= existingTrimmed.count ? incoming : existing
    }

    /// 多 variant 合并时优先无 query、HTTPS 的图片链接，避免 litbimg `?f=0` 等参数导致 CDN 403。
    static func pickBetterImageURL(_ existing: String?, _ incoming: String?) -> String? {
        let existingTrimmed = existing?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let incomingTrimmed = incoming?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if existingTrimmed.isEmpty { return incomingTrimmed.isEmpty ? existing : incoming }
        if incomingTrimmed.isEmpty { return existing }

        let existingScore = imageURLPreferenceScore(existingTrimmed)
        let incomingScore = imageURLPreferenceScore(incomingTrimmed)
        if incomingScore != existingScore {
            return incomingScore > existingScore ? incoming : existing
        }
        return incomingTrimmed.count >= existingTrimmed.count ? incoming : existing
    }

    private static func imageURLPreferenceScore(_ raw: String) -> Int {
        var score = 0
        let lowercased = raw.lowercased()
        if lowercased.hasPrefix("https://") {
            score += 2
        } else if lowercased.hasPrefix("http://") {
            score += 1
        }
        if !raw.contains("?") {
            score += 4
        }
        if lowercased.contains("f=0") {
            score -= 2
        }
        return score
    }

    static func merge(into target: inout ProductRecord, from source: ProductRecord) {
        target.title = pickBetterString(target.title, source.title)
        target.canonicalLink = pickBetterString(target.canonicalLink, source.canonicalLink)
        target.imageUrl = pickBetterImageURL(target.imageUrl, source.imageUrl)
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
        if let incomingListed = source.firstListedAt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !incomingListed.isEmpty {
            if let existingListed = target.firstListedAt?.trimmingCharacters(in: .whitespacesAndNewlines),
               !existingListed.isEmpty {
                target.firstListedAt = min(existingListed, incomingListed)
            } else {
                target.firstListedAt = incomingListed
            }
        }
        target.plaCms3 = pickBetterString(target.plaCms3, source.plaCms3)
        target.updatedFromImportId = pickBetterString(target.updatedFromImportId, source.updatedFromImportId)
    }
}
