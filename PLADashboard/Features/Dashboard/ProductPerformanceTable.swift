import SwiftUI

/// macOS 产品表现表 — 官方 `Table` + 列头排序（消费、ROI）。
struct ProductPerformanceTable: View {
    let rows: [ProductPerformanceRowModel]
    let isSidebarVisible: Bool
    @Binding var sortOrder: [KeyPathComparator<ProductPerformanceRowModel>]

    var body: some View {
        Group {
            if isSidebarVisible {
                expandedTable
            } else {
                collapsedTable
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var expandedTable: some View {
        Table(rows, sortOrder: $sortOrder) {
            Group {
                lsinColumn
                productImageColumn
                costColumn
                roiColumn
                warningLabelColumn
                costTrendColumn
                gsTrendColumn
                cpaColumn
                arpuColumn
                cpcColumn
            }
            Group {
                cvrColumn
                aosColumn
            }
        }
    }

    private var collapsedTable: some View {
        Table(rows, sortOrder: $sortOrder) {
            Group {
                lsinColumn
                productImageColumn
                costColumn
                roiColumn
                warningLabelColumn
                costTrendColumn
                gsTrendColumn
                cpaColumn
                arpuColumn
                cpcColumn
            }
            Group {
                cvrColumn
                aosColumn
                clicksColumn
                conversionsColumn
            }
        }
    }

    private var lsinColumn: some TableColumnContent<ProductPerformanceRowModel, KeyPathComparator<ProductPerformanceRowModel>> {
        column(DashboardColumn.lsin, value: \.sortLSIN) { row in
            Text(row.lsin).font(.body)
        }
    }

    private var productImageColumn: some TableColumnContent<ProductPerformanceRowModel, KeyPathComparator<ProductPerformanceRowModel>> {
        column(DashboardColumn.productImage, value: \.sortLSIN) { row in
            ProductImageView(imageURL: row.imageURL)
        }
    }

    private var costColumn: some TableColumnContent<ProductPerformanceRowModel, KeyPathComparator<ProductPerformanceRowModel>> {
        column(DashboardColumn.cost, value: \.sortCostCents) { row in
            VStack(alignment: .leading, spacing: 2) {
                Text(row.cost).font(.body)
                Text(row.costShare).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var roiColumn: some TableColumnContent<ProductPerformanceRowModel, KeyPathComparator<ProductPerformanceRowModel>> {
        column(DashboardColumn.roi, value: \.sortROI) { row in
            Text(row.roi).font(.body)
        }
    }

    private var warningLabelColumn: some TableColumnContent<ProductPerformanceRowModel, KeyPathComparator<ProductPerformanceRowModel>> {
        column(DashboardColumn.warningLabel, value: \.sortLSIN) { row in
            WarningLabelView(text: row.warningLabel, style: row.warningStyle)
        }
    }

    private var costTrendColumn: some TableColumnContent<ProductPerformanceRowModel, KeyPathComparator<ProductPerformanceRowModel>> {
        column(DashboardColumn.costTrend, value: \.sortCostCents) { row in
            WeeklyTrendBarChart(values: row.costTrendWeeks)
        }
    }

    private var gsTrendColumn: some TableColumnContent<ProductPerformanceRowModel, KeyPathComparator<ProductPerformanceRowModel>> {
        column(DashboardColumn.gsTrend, value: \.sortCostCents) { row in
            WeeklyTrendBarChart(values: row.gsTrendWeeks, style: .sales)
        }
    }

    private var cpaColumn: some TableColumnContent<ProductPerformanceRowModel, KeyPathComparator<ProductPerformanceRowModel>> {
        column(DashboardColumn.cpa, value: \.sortROI) { row in
            MetricDeltaCell(value: row.cpa, delta: row.cpaDelta, polarity: .lowerIsBetter)
        }
    }

    private var arpuColumn: some TableColumnContent<ProductPerformanceRowModel, KeyPathComparator<ProductPerformanceRowModel>> {
        column(DashboardColumn.arpu, value: \.sortROI) { row in
            MetricDeltaCell(value: row.arpu, delta: row.arpuDelta, polarity: .higherIsBetter)
        }
    }

    private var cpcColumn: some TableColumnContent<ProductPerformanceRowModel, KeyPathComparator<ProductPerformanceRowModel>> {
        column(DashboardColumn.cpc, value: \.sortROI) { row in
            MetricDeltaCell(value: row.cpc, delta: row.cpcDelta, polarity: .lowerIsBetter)
        }
    }

    private var cvrColumn: some TableColumnContent<ProductPerformanceRowModel, KeyPathComparator<ProductPerformanceRowModel>> {
        column(DashboardColumn.cvr, value: \.sortROI) { row in
            MetricDeltaCell(value: row.cvr, delta: row.cvrDelta, polarity: .higherIsBetter)
        }
    }

    private var aosColumn: some TableColumnContent<ProductPerformanceRowModel, KeyPathComparator<ProductPerformanceRowModel>> {
        column(DashboardColumn.aos, value: \.sortROI) { row in
            MetricDeltaCell(value: row.aos, delta: row.aosDelta, polarity: .higherIsBetter)
        }
    }

    private var clicksColumn: some TableColumnContent<ProductPerformanceRowModel, KeyPathComparator<ProductPerformanceRowModel>> {
        column(DashboardColumn.clicks, value: \.sortClicks) { row in
            Text(row.clicks ?? "—").font(.body)
        }
    }

    private var conversionsColumn: some TableColumnContent<ProductPerformanceRowModel, KeyPathComparator<ProductPerformanceRowModel>> {
        column(DashboardColumn.conversions, value: \.sortLSIN) { row in
            Text(row.conversions ?? "—").font(.body)
        }
    }

    private func column<Value: Comparable, Content: View>(
        _ dashboardColumn: DashboardColumn,
        value: KeyPath<ProductPerformanceRowModel, Value>,
        @ViewBuilder content: @escaping (ProductPerformanceRowModel) -> Content
    ) -> some TableColumnContent<ProductPerformanceRowModel, KeyPathComparator<ProductPerformanceRowModel>> {
        TableColumn(dashboardColumn.rawValue, value: value) { row in
            rowCell(row) {
                content(row)
            }
        }
        .width(
            min: dashboardColumn.widthSpec.min,
            ideal: dashboardColumn.widthSpec.ideal,
            max: dashboardColumn.widthSpec.max
        )
    }

    private func rowCell<Content: View>(
        _ row: ProductPerformanceRowModel,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .accessibilityElement(children: .combine)
            .accessibilityLabel(row.accessibilitySummary)
    }
}
