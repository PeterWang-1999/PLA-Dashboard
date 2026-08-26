import SwiftUI
import Charts
import AppKit

struct CategoryBubbleChart: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let points: [DataDashboardCategoryPoint]
    @State private var hoveredCategoryID: String?

    private let palette: [Color] = [
        .blue, .green, .orange, .purple, .teal, .pink, .indigo, .mint, .cyan, .brown,
    ]

    private var maxCost: Double {
        max(1, points.map { Double($0.metrics.costCents) / 100 }.max() ?? 0) * 1.08
    }

    private var maxROI: Double {
        max(0.1, points.map(\.metrics.roi).max() ?? 0) * 1.12
    }

    var body: some View {
        Chart(points) { point in
            PointMark(
                x: .value("投放成本", Double(point.metrics.costCents) / 100),
                y: .value("ROI", point.metrics.roi)
            )
            .symbolSize(by: .value("销售额", max(1, Double(point.metrics.conversionValueCents) / 100)))
            .foregroundStyle(color(for: point).opacity(hoveredCategoryID == nil || hoveredCategoryID == point.id ? 0.78 : 0.3))
            .annotation(position: .top, spacing: 4) {
                Text(point.category)
                    .font(.caption.weight(hoveredCategoryID == point.id ? .semibold : .regular))
                    .lineLimit(1)
            }
        }
        .chartXAxisLabel("投放成本（USD）")
        .chartYAxisLabel("广告 ROI")
        .chartLegend(.hidden)
        .chartXScale(domain: 0...maxCost, range: .plotDimension(padding: 34))
        .chartYScale(domain: 0...maxROI, range: .plotDimension(padding: 24))
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(location):
                            updateHover(at: location, proxy: proxy, geometry: geometry)
                        case .ended:
                            clearHover()
                        }
                    }
            }
        }
        .frame(height: 380)
        .accessibilityLabel("类目消费、ROI 与销售额气泡图")
        .onDisappear { clearHover() }
    }

    private func color(for point: DataDashboardCategoryPoint) -> Color {
        let stableIndex = point.category.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % palette.count }
        return palette[stableIndex]
    }

    private func updateHover(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        let plotFrame = geometry[proxy.plotFrame!]
        let local = CGPoint(x: location.x - plotFrame.origin.x, y: location.y - plotFrame.origin.y)
        guard local.x >= 0, local.y >= 0, local.x <= plotFrame.width, local.y <= plotFrame.height else {
            clearHover()
            return
        }
        let nearest = points.compactMap { point -> (DataDashboardCategoryPoint, CGFloat)? in
            guard let x = proxy.position(forX: Double(point.metrics.costCents) / 100),
                  let y = proxy.position(forY: point.metrics.roi) else { return nil }
            return (point, hypot(x - local.x, y - local.y))
        }.min { $0.1 < $1.1 }

        guard let nearest, nearest.1 <= 42 else {
            clearHover()
            return
        }
        hoveredCategoryID = nearest.0.id
        TrendHoverPanelController.shared.show(
            id: "category-\(nearest.0.id)",
            at: NSEvent.mouseLocation,
            content: AnyView(categoryHoverPanel(for: nearest.0))
        )
    }

    private func clearHover() {
        hoveredCategoryID = nil
        TrendHoverPanelController.shared.hide()
    }

    private func categoryHoverPanel(for point: DataDashboardCategoryPoint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle().fill(color(for: point)).frame(width: 8, height: 8)
                Text(point.category).font(.headline)
            }
            Text("当前筛选范围 · 环比为近 2 周")
                .font(.caption)
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                categoryMetricRow("消费占比", value: point.spendShare.formatted(.percent.precision(.fractionLength(1))))
                categoryMetricRow("销售占比", value: point.salesShare.formatted(.percent.precision(.fractionLength(1))))
                categoryMetricRow(
                    "ROI",
                    value: DashboardMetricFormatter.formatDecimal(point.metrics.roi, fractionDigits: 2),
                    comparison: meanComparison(point.metrics.roi, average: point.portfolioROI),
                    comparisonPrefix: "较均值"
                )
                categoryMetricRow(
                    "CVR",
                    value: DashboardMetricFormatter.formatPercentValue(point.currentWeekMetrics.cvr),
                    comparison: weekDelta(point.currentWeekMetrics.cvr, point.previousWeekMetrics.cvr)
                )
                categoryMetricRow(
                    "AOS",
                    value: point.currentWeekMetrics.aos.formatted(.currency(code: "USD").precision(.fractionLength(2))),
                    comparison: weekDelta(point.currentWeekMetrics.aos, point.previousWeekMetrics.aos)
                )
                categoryMetricRow(
                    "CPC",
                    value: point.currentWeekMetrics.cpc.formatted(.currency(code: "USD").precision(.fractionLength(2))),
                    comparison: weekDelta(point.currentWeekMetrics.cpc, point.previousWeekMetrics.cpc),
                    inverted: true
                )
            }
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            reduceTransparency
                ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
                : AnyShapeStyle(.regularMaterial),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.separator.opacity(0.65), lineWidth: 0.5)
        }
        .padding(8)
        .fixedSize()
    }

    private func categoryMetricRow(
        _ title: String,
        value: String,
        comparison: Double? = nil,
        comparisonPrefix: String? = nil,
        inverted: Bool = false
    ) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            HStack(spacing: 5) {
                Text(value)
                if let comparison {
                    Text("\(comparisonPrefix.map { "\($0) " } ?? "")\(String(format: "%+.1f%%", comparison * 100))")
                        .foregroundStyle(deltaColor(comparison, inverted: inverted))
                }
            }
            .monospacedDigit()
        }
    }

    private func meanComparison(_ value: Double, average: Double) -> Double? {
        average != 0 ? (value - average) / abs(average) : nil
    }

    private func weekDelta(_ value: Double, _ previous: Double) -> Double? {
        previous != 0 ? (value - previous) / abs(previous) : nil
    }

    private func deltaColor(_ delta: Double, inverted: Bool) -> Color {
        guard delta != 0 else { return .secondary }
        return (inverted ? delta < 0 : delta > 0) ? .green : .red
    }
}
