import SwiftUI

struct MetricDeltaCell: View {
    let value: String
    let delta: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.body)
            Text(delta)
                .font(.caption)
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

struct WarningLabelView: View {
    let text: String
    let style: ProductPerformanceRowModel.WarningLabelStyle

    var body: some View {
        if style == .none || text == "—" {
            Text("—")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text(text)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(backgroundColor)
                .foregroundStyle(foregroundColor)
                .clipShape(Capsule())
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .none:
            .clear
        case .lowSpend:
            Color.blue.opacity(0.15)
        case .highSpendHighEfficiency:
            Color.green.opacity(0.15)
        case .highSpendLowEfficiency:
            Color.red.opacity(0.15)
        case .highSpend:
            Color.orange.opacity(0.18)
        case .lowEfficiency:
            Color.orange.opacity(0.22)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .none:
            .secondary
        case .lowSpend:
            .blue
        case .highSpendHighEfficiency:
            .green
        case .highSpendLowEfficiency:
            .red
        case .highSpend:
            .orange
        case .lowEfficiency:
            .orange
        }
    }
}
