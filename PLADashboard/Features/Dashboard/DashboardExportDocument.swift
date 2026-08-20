import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct DashboardExportCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    let text: String

    init(
        bundle: DashboardExportBundle,
        filters: DashboardQueryFilters,
        includeClicksAndConversions: Bool
    ) {
        text = Self.makeCSV(
            bundle: bundle,
            filters: filters,
            includeClicksAndConversions: includeClicksAndConversions
        )
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

    private static func makeCSV(
        bundle: DashboardExportBundle,
        filters: DashboardQueryFilters,
        includeClicksAndConversions: Bool
    ) -> String {
        var lines: [String] = []
        let exportedAt = ISO8601DateFormatter().string(from: Date())
        lines.append("# exported_at=\(exportedAt)")
        lines.append("# row_count=\(bundle.totalCount)")
        lines.append("# weeks=\(bundle.weekStarts.joined(separator: ","))")
        lines.append("# search=\(Self.escapeCSV(filters.searchText))")
        lines.append("# alert_filter=\(Self.escapeCSV(filters.alertFilter))")
        lines.append("# custom_label_filter=\(Self.escapeCSV(filters.customLabelFilter.menuTitle))")
        lines.append("# category_filter=\(Self.escapeCSV(filters.categoryFilter.menuTitle))")
        lines.append("# sort=\(Self.escapeCSV(filters.sort.exportLabel))")

        var headers = [
            "产品 ID", "消费", "消费占比", "ROI", "预警标签",
        ]
        for week in bundle.weekStarts {
            headers.append("消费趋势_\(week)")
        }
        for week in bundle.weekStarts {
            headers.append("销售趋势_\(week)")
        }
        headers += ["CPA", "CPA偏差", "ARPU", "ARPU偏差", "CPC", "CPC偏差", "CVR", "CVR偏差", "AOS", "AOS偏差"]
        if includeClicksAndConversions {
            headers += ["点击次数", "转化次数"]
        }
        lines.append(headers.joined(separator: ","))

        for row in bundle.rows {
            var fields: [String] = [
                Self.escapeCSV(row.lsin),
                Self.escapeCSV(row.cost),
                Self.escapeCSV(row.costShare),
                Self.escapeCSV(row.roi),
                Self.escapeCSV(row.warningLabel),
            ]
            for cents in row.costTrendWeeks.prefix(bundle.weekStarts.count) {
                fields.append(Self.escapeCSV(DashboardMetricFormatter.formatCurrencyFromCents(cents)))
            }
            for cents in row.gsTrendWeeks.prefix(bundle.weekStarts.count) {
                fields.append(Self.escapeCSV(DashboardMetricFormatter.formatCurrencyFromCents(cents)))
            }
            fields += [
                Self.escapeCSV(row.cpa),
                Self.escapeCSV(row.cpaDelta),
                Self.escapeCSV(row.arpu),
                Self.escapeCSV(row.arpuDelta),
                Self.escapeCSV(row.cpc),
                Self.escapeCSV(row.cpcDelta),
                Self.escapeCSV(row.cvr),
                Self.escapeCSV(row.cvrDelta),
                Self.escapeCSV(row.aos),
                Self.escapeCSV(row.aosDelta),
            ]
            if includeClicksAndConversions {
                fields.append(Self.escapeCSV(row.clicks ?? "—"))
                fields.append(Self.escapeCSV(row.conversions ?? "—"))
            }
            lines.append(fields.joined(separator: ","))
        }

        return lines.joined(separator: "\n")
    }

    private static func escapeCSV(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
