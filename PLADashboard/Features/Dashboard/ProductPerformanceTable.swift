import SwiftUI

/// macOS 产品表现表 — 使用官方 `Table` + `TableColumnForEach` + `TableColumn.width(min:ideal:max:)`。
struct ProductPerformanceTable: View {
    let rows: [ProductPerformanceRowModel]
    let isSidebarVisible: Bool

    private var visibleColumns: [DashboardColumn] {
        DashboardColumnLayout.visibleColumns(isSidebarVisible: isSidebarVisible)
    }

    var body: some View {
        Table(rows) {
            TableColumnForEach(visibleColumns) { column in
                TableColumn(column.rawValue) { row in
                    cellContent(for: column, row: row)
                }
                .width(
                    min: column.widthSpec.min,
                    ideal: column.widthSpec.ideal,
                    max: column.widthSpec.max
                )
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func cellContent(for column: DashboardColumn, row: ProductPerformanceRowModel) -> some View {
        switch column {
        case .lsin:
            Text(row.lsin)
                .font(.body)

        case .productImage:
            ProductImageView(imageURL: row.imageURL)

        case .cost:
            VStack(alignment: .leading, spacing: 2) {
                Text(row.cost).font(.body)
                Text(row.costShare).font(.caption).foregroundStyle(.secondary)
            }

        case .roi:
            Text(row.roi).font(.body)

        case .warningLabel:
            WarningLabelView(text: row.warningLabel, style: row.warningStyle)

        case .costTrend:
            WeeklyTrendBarChart(values: row.costTrendWeeks)

        case .gsTrend:
            WeeklyTrendBarChart(values: row.gsTrendWeeks, style: .sales)

        case .cpa:
            MetricDeltaCell(value: row.cpa, delta: row.cpaDelta)

        case .arpu:
            MetricDeltaCell(value: row.arpu, delta: row.arpuDelta)

        case .cpc:
            MetricDeltaCell(value: row.cpc, delta: row.cpcDelta)

        case .cvr:
            MetricDeltaCell(value: row.cvr, delta: row.cvrDelta)

        case .aos:
            MetricDeltaCell(value: row.aos, delta: row.aosDelta)

        case .clicks:
            Text(row.clicks ?? "—").font(.body)

        case .conversions:
            Text(row.conversions ?? "—").font(.body)
        }
    }
}
