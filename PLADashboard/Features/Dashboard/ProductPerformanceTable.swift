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
            }
            costColumn
            roiColumn
            Group {
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
            }
            costColumn
            roiColumn
            Group {
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

    private var lsinColumn: some TableColumnContent<ProductPerformanceRowModel, Never> {
        staticColumn(DashboardColumn.lsin, accessibilityValue: \.lsin) { row in
            Text(row.lsin).font(.body)
        }
    }

    private var productImageColumn: some TableColumnContent<ProductPerformanceRowModel, Never> {
        staticColumn(DashboardColumn.productImage, accessibilityValue: { row in
            row.imageURL == nil ? "无图片" : "产品 \(row.lsin) 的图片"
        }) { row in
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

    private var warningLabelColumn: some TableColumnContent<ProductPerformanceRowModel, Never> {
        staticColumn(DashboardColumn.warningLabel, accessibilityValue: \.warningLabel) { row in
            WarningLabelView(text: row.warningLabel, style: row.warningStyle)
        }
    }

    private var costTrendColumn: some TableColumnContent<ProductPerformanceRowModel, Never> {
        staticColumn(DashboardColumn.costTrend, accessibilityValue: { row in
            trendAccessibilityValue(row.costTrendWeeks)
        }) { row in
            WeeklyTrendBarChart(values: row.costTrendWeeks)
        }
    }

    private var gsTrendColumn: some TableColumnContent<ProductPerformanceRowModel, Never> {
        staticColumn(DashboardColumn.gsTrend, accessibilityValue: { row in
            trendAccessibilityValue(row.gsTrendWeeks)
        }) { row in
            WeeklyTrendBarChart(values: row.gsTrendWeeks, style: .sales)
        }
    }

    private var cpaColumn: some TableColumnContent<ProductPerformanceRowModel, Never> {
        staticColumn(DashboardColumn.cpa, accessibilityValue: { "\($0.cpa)，相较整体 \($0.cpaDelta)" }) { row in
            MetricDeltaCell(value: row.cpa, delta: row.cpaDelta, polarity: .lowerIsBetter)
        }
    }

    private var arpuColumn: some TableColumnContent<ProductPerformanceRowModel, Never> {
        staticColumn(DashboardColumn.arpu, accessibilityValue: { "\($0.arpu)，相较整体 \($0.arpuDelta)" }) { row in
            MetricDeltaCell(value: row.arpu, delta: row.arpuDelta, polarity: .higherIsBetter)
        }
    }

    private var cpcColumn: some TableColumnContent<ProductPerformanceRowModel, Never> {
        staticColumn(DashboardColumn.cpc, accessibilityValue: { "\($0.cpc)，相较整体 \($0.cpcDelta)" }) { row in
            MetricDeltaCell(value: row.cpc, delta: row.cpcDelta, polarity: .lowerIsBetter)
        }
    }

    private var cvrColumn: some TableColumnContent<ProductPerformanceRowModel, Never> {
        staticColumn(DashboardColumn.cvr, accessibilityValue: { "\($0.cvr)，相较整体 \($0.cvrDelta)" }) { row in
            MetricDeltaCell(value: row.cvr, delta: row.cvrDelta, polarity: .higherIsBetter)
        }
    }

    private var aosColumn: some TableColumnContent<ProductPerformanceRowModel, Never> {
        staticColumn(DashboardColumn.aos, accessibilityValue: { "\($0.aos)，相较整体 \($0.aosDelta)" }) { row in
            MetricDeltaCell(value: row.aos, delta: row.aosDelta, polarity: .higherIsBetter)
        }
    }

    private var clicksColumn: some TableColumnContent<ProductPerformanceRowModel, Never> {
        staticColumn(DashboardColumn.clicks, accessibilityValue: { $0.clicks ?? "无数据" }) { row in
            Text(row.clicks ?? "—").font(.body)
        }
    }

    private var conversionsColumn: some TableColumnContent<ProductPerformanceRowModel, Never> {
        staticColumn(DashboardColumn.conversions, accessibilityValue: { $0.conversions ?? "无数据" }) { row in
            Text(row.conversions ?? "—").font(.body)
        }
    }

    private func column<Value: Comparable, Content: View>(
        _ dashboardColumn: DashboardColumn,
        value: KeyPath<ProductPerformanceRowModel, Value>,
        @ViewBuilder content: @escaping (ProductPerformanceRowModel) -> Content
    ) -> some TableColumnContent<ProductPerformanceRowModel, KeyPathComparator<ProductPerformanceRowModel>> {
        TableColumn(dashboardColumn.rawValue, value: value) { row in
            accessibleCell(column: dashboardColumn, value: displayedValue(for: dashboardColumn, row: row)) {
                content(row)
            }
        }
        .width(
            min: dashboardColumn.widthSpec.min,
            ideal: dashboardColumn.widthSpec.ideal,
            max: dashboardColumn.widthSpec.max
        )
    }

    private func staticColumn<Content: View>(
        _ dashboardColumn: DashboardColumn,
        accessibilityValue: @escaping (ProductPerformanceRowModel) -> String,
        @ViewBuilder content: @escaping (ProductPerformanceRowModel) -> Content
    ) -> some TableColumnContent<ProductPerformanceRowModel, Never> {
        TableColumn(dashboardColumn.rawValue) { row in
            accessibleCell(column: dashboardColumn, value: accessibilityValue(row)) {
                content(row)
            }
        }
        .width(
            min: dashboardColumn.widthSpec.min,
            ideal: dashboardColumn.widthSpec.ideal,
            max: dashboardColumn.widthSpec.max
        )
    }

    private func staticColumn<Value, Content: View>(
        _ dashboardColumn: DashboardColumn,
        accessibilityValue: KeyPath<ProductPerformanceRowModel, Value>,
        @ViewBuilder content: @escaping (ProductPerformanceRowModel) -> Content
    ) -> some TableColumnContent<ProductPerformanceRowModel, Never> where Value: StringProtocol {
        staticColumn(dashboardColumn, accessibilityValue: { String($0[keyPath: accessibilityValue]) }, content: content)
    }

    private func accessibleCell<Content: View>(
        column: DashboardColumn,
        value: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(column.rawValue)，\(value)")
    }

    private func displayedValue(
        for column: DashboardColumn,
        row: ProductPerformanceRowModel
    ) -> String {
        switch column {
        case .cost: "\(row.cost)，占总消费 \(row.costShare)"
        case .roi: row.roi
        default: ""
        }
    }

    private func trendAccessibilityValue(_ values: [Int]) -> String {
        guard !values.isEmpty else { return "无数据" }
        return values.enumerated()
            .map { "第 \($0.offset + 1) 周 \($0.element)" }
            .joined(separator: "，")
    }
}
