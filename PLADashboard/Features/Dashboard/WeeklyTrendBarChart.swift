import SwiftUI
import Charts

/// 表格单元格内的六周迷你柱状图（Swift Charts `BarMark`）。
struct WeeklyTrendBarChart: View {
    enum Style {
        case cost
        /// 销售趋势：展示 Google Ads Conversion Value 周汇总（cents → 金额）。
        case sales

        var barColor: Color {
            switch self {
            case .cost:
                Color.accentColor.opacity(0.85)
            case .sales:
                Color.orange.opacity(0.85)
            }
        }

        var accessibilitySeriesName: String {
            switch self {
            case .cost:
                "消费趋势"
            case .sales:
                "销售趋势"
            }
        }

        /// 分类轴上 `.ratio` 表示柱宽占类目间距的比例；销售趋势更紧凑。
        var barWidthRatio: CGFloat {
            switch self {
            case .cost:
                0.88
            case .sales:
                0.94
            }
        }
    }

    let values: [Int]
    var style: Style = .cost

    private struct WeekPoint: Identifiable {
        let weekLabel: String
        let value: Double

        var id: String { weekLabel }
    }

    private var points: [WeekPoint] {
        values.enumerated().map { index, cents in
            WeekPoint(weekLabel: "W\(index)", value: Double(cents) / 100)
        }
    }

    private var accessibilitySummary: String {
        let series = style.accessibilitySeriesName
        guard values.contains(where: { $0 > 0 }) else {
            return "\(series)：近六周无数据"
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let amounts = values.enumerated().map { index, cents -> String in
            let amount = Double(cents) / 100
            let formatted = formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
            return "第\(index + 1)周 \(formatted)"
        }
        return "\(series)：\(amounts.joined(separator: "，"))"
    }

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Week", point.weekLabel),
                y: .value("Value", point.value),
                width: .ratio(style.barWidthRatio)
            )
            .foregroundStyle(style.barColor)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(minWidth: 50, idealWidth: 65, maxWidth: .infinity, minHeight: 28, idealHeight: 28, maxHeight: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }
}
