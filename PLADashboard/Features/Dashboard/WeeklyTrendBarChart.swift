import SwiftUI
import Charts

/// 表格单元格内的六周迷你柱状图（Swift Charts `BarMark`）。
struct WeeklyTrendBarChart: View {
    enum Style {
        case cost
        case sales

        var barColor: Color {
            switch self {
            case .cost:
                Color.accentColor.opacity(0.85)
            case .sales:
                Color(red: 1.0, green: 0.62, blue: 0.18).opacity(0.9)
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
    }
}
