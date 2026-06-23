import SwiftUI
import Charts

struct WeeklyTrendBarChart: View {
    let values: [Int]

    private struct WeekPoint: Identifiable {
        let id: Int
        let value: Double
    }

    private var points: [WeekPoint] {
        values.enumerated().map { index, cents in
            WeekPoint(id: index, value: Double(cents) / 100)
        }
    }

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Week", point.id),
                y: .value("Value", point.value)
            )
            .foregroundStyle(Color.accentColor.opacity(0.85))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(minWidth: 56, idealWidth: 96, maxWidth: .infinity, minHeight: 28, maxHeight: 28)
    }
}
