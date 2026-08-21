import Foundation

struct ProductDetailModel: Sendable {
    let productID: String
    let title: String?
    let imageURL: URL?
    let canonicalURL: URL?
    let customLabels: [String?]
    let skuRows: [ProductDetailSKURow]
    let periodStart: String
    let periodEnd: String
}

struct ProductDetailSKURow: Identifiable, Hashable, Sendable {
    let itemID: String
    let variantID: String?
    let currencyCode: String
    let costMicros: Int
    let clicks: Int
    let conversions: Double
    let conversionValueCents: Int

    var id: String { itemID }

    var roi: Double? {
        guard costMicros > 0 else { return nil }
        return Double(conversionValueCents) * 10_000 / Double(costMicros)
    }

    var displayCost: String {
        DashboardMetricFormatter.formatDecimal(Double(costMicros) / 1_000_000, fractionDigits: 2)
    }

    var displayROI: String {
        guard let roi else { return "—" }
        return DashboardMetricFormatter.formatDecimal(roi, fractionDigits: 2)
    }

    var displayClicks: String {
        DashboardMetricFormatter.formatInteger(clicks)
    }

    var displayConversions: String {
        let fractionDigits = conversions.rounded() == conversions ? 0 : 2
        return DashboardMetricFormatter.formatDecimal(conversions, fractionDigits: fractionDigits)
    }
}

enum ProductDetailError: LocalizedError {
    case unsupportedAccount
    case missingReportingPeriod
    case productNotFound

    var errorDescription: String? {
        switch self {
        case .unsupportedAccount:
            "产品明细目前仅支持三方站账户。"
        case .missingReportingPeriod:
            "当前看板没有可用的数据周期。"
        case .productNotFound:
            "未找到该产品的基础信息。"
        }
    }
}
