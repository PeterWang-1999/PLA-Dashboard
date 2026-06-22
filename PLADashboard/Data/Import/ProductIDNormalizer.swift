import Foundation

enum ProductIDSourceFormat: String, Sendable {
    case shopifyItemID = "shopify_item_id"
    case underscorePrefix = "underscore_prefix"
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
