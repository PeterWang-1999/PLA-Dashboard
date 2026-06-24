import SwiftUI

struct MetricDeltaCell: View {
    let value: String
    let delta: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.body)
            HStack(spacing: 2) {
                if let symbol = deltaSymbol {
                    Image(systemName: symbol)
                        .font(.caption2)
                        .accessibilityHidden(true)
                }
                Text(delta)
                    .font(.caption)
            }
            .foregroundStyle(deltaForegroundStyle)
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value)，相较整体 \(deltaAccessibilityDescription)")
    }

    private var deltaSymbol: String? {
        if delta.hasPrefix("+") { return "arrowtriangle.up.fill" }
        if delta.hasPrefix("-") { return "arrowtriangle.down.fill" }
        return nil
    }

    private var deltaForegroundStyle: AnyShapeStyle {
        if delta.hasPrefix("+") || delta.hasPrefix("-") {
            AnyShapeStyle(.primary)
        } else {
            AnyShapeStyle(.secondary)
        }
    }

    private var deltaAccessibilityDescription: String {
        if delta.hasPrefix("+") { return "上升 \(delta)" }
        if delta.hasPrefix("-") { return "下降 \(delta.dropFirst())" }
        return delta
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
            Label {
                Text(text)
                    .font(.caption.weight(.medium))
            } icon: {
                Image(systemName: warningSymbol)
                    .font(.caption2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
            .accessibilityLabel("预警标签，\(text)")
        }
    }

    private var warningSymbol: String {
        switch style {
        case .none:
            "minus.circle"
        case .lowSpend:
            "arrow.down.circle"
        case .highSpendHighEfficiency:
            "checkmark.circle"
        case .highSpendLowEfficiency:
            "exclamationmark.triangle"
        case .highSpend:
            "flame"
        case .lowEfficiency:
            "gauge.with.dots.needle.33percent"
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
