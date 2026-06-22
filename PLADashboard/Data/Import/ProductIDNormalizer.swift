import Foundation

enum ProductIDSourceFormat: String, Sendable {
    case shopifyItemID = "shopify_item_id"
    case underscorePrefix = "underscore_prefix"
    case lsinPrefix = "lsin_prefix"
    case empty
    case invalid
}

enum ProductIDMatchConfidence: String, Sendable {
    case high
    case medium
    case low
}

struct NormalizedProductIdentifier: Sendable, Equatable {
    let rawValue: String
    let productID: String
    let variantID: String?
    let sourceFormat: ProductIDSourceFormat
    let confidence: ProductIDMatchConfidence
}

enum ProductIDNormalizer {
    private static let shopifyPattern = try! NSRegularExpression(
        pattern: #"^shopify_[a-z]+_([0-9]+)_([0-9]+)$"#,
        options: [.caseInsensitive]
    )

    private static let lsinPattern = try! NSRegularExpression(
        pattern: #"^S([0-9]+)$"#,
        options: [.caseInsensitive]
    )

    static func normalize(_ rawValue: String) -> NormalizedProductIdentifier {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return NormalizedProductIdentifier(
                rawValue: rawValue,
                productID: "",
                variantID: nil,
                sourceFormat: .empty,
                confidence: .low
            )
        }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        if let match = shopifyPattern.firstMatch(in: trimmed, range: range),
           match.numberOfRanges >= 3,
           let productRange = Range(match.range(at: 1), in: trimmed),
           let variantRange = Range(match.range(at: 2), in: trimmed) {
            return NormalizedProductIdentifier(
                rawValue: trimmed,
                productID: String(trimmed[productRange]),
                variantID: String(trimmed[variantRange]),
                sourceFormat: .shopifyItemID,
                confidence: .high
            )
        }

        if let underscoreIndex = trimmed.firstIndex(of: "_") {
            let prefix = String(trimmed[..<underscoreIndex])
            guard !prefix.isEmpty else {
                return invalidIdentifier(rawValue: trimmed)
            }
            return NormalizedProductIdentifier(
                rawValue: trimmed,
                productID: prefix,
                variantID: nil,
                sourceFormat: .underscorePrefix,
                confidence: .medium
            )
        }

        return NormalizedProductIdentifier(
            rawValue: trimmed,
            productID: trimmed,
            variantID: nil,
            sourceFormat: .underscorePrefix,
            confidence: .medium
        )
    }

    /// 自归因 LSIN：`S14429548` → `product_id = 14429548`，保留原始 `lsin`。
    static func normalizeLSIN(_ lsin: String) -> NormalizedProductIdentifier {
        let trimmed = lsin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return NormalizedProductIdentifier(
                rawValue: lsin,
                productID: "",
                variantID: nil,
                sourceFormat: .empty,
                confidence: .low
            )
        }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        if let match = lsinPattern.firstMatch(in: trimmed, range: range),
           match.numberOfRanges >= 2,
           let digitsRange = Range(match.range(at: 1), in: trimmed) {
            return NormalizedProductIdentifier(
                rawValue: trimmed,
                productID: String(trimmed[digitsRange]),
                variantID: nil,
                sourceFormat: .lsinPrefix,
                confidence: .high
            )
        }

        let fallback = normalize(trimmed)
        return NormalizedProductIdentifier(
            rawValue: trimmed,
            productID: fallback.productID,
            variantID: fallback.variantID,
            sourceFormat: fallback.sourceFormat,
            confidence: .medium
        )
    }

    private static func invalidIdentifier(rawValue: String) -> NormalizedProductIdentifier {
        NormalizedProductIdentifier(
            rawValue: rawValue,
            productID: "",
            variantID: nil,
            sourceFormat: .invalid,
            confidence: .low
        )
    }
}
