import SwiftUI

struct MetricDeltaCell: View {
    let value: String
    let delta: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 13))
            Text(delta)
                .font(.system(size: 11))
                .foregroundStyle(deltaColor)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var deltaColor: Color {
        if delta.hasPrefix("+") { return .green }
        if delta.hasPrefix("-") { return .red }
        return .secondary
    }
}

struct TrendPlaceholderView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.accentColor.opacity(0.15))
            .frame(width: 52, height: 28)
            .overlay {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
    }
}

struct WarningLabelView: View {
    let text: String
    let style: ProductPerformanceRowModel.WarningLabelStyle

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch style {
        case .normal: Color.green.opacity(0.15)
        case .warning: Color.orange.opacity(0.18)
        case .critical: Color.red.opacity(0.15)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }
}
