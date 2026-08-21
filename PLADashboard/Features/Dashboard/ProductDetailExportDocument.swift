import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ProductDetailExportCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    let text: String

    init(detail: ProductDetailModel) {
        var lines = [
            "# product_id=\(Self.escape(detail.productID))",
            "# period_start=\(detail.periodStart)",
            "# period_end=\(detail.periodEnd)",
            "SKU,Variant ID,Currency,Cost,ROI,Clicks,Conversions,Conversion Value",
        ]
        lines += detail.skuRows.map { row in
            [
                row.itemID,
                row.variantID ?? "",
                row.currencyCode,
                row.displayCost,
                row.displayROI,
                row.displayClicks,
                row.displayConversions,
                DashboardMetricFormatter.formatCurrencyFromCents(row.conversionValueCents),
            ]
            .map(Self.escape)
            .joined(separator: ",")
        }
        text = lines.joined(separator: "\n")
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(contentsOf: text.utf8)
        return FileWrapper(regularFileWithContents: data)
    }

    private static func escape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
