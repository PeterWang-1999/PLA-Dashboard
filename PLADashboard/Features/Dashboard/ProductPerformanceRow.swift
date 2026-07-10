import SwiftUI

enum MetricDeltaPolarity: Sendable {
    /// CPA、CPC：高于整体为劣（红），低于整体为优（绿）
    case lowerIsBetter
    /// ARPU、CVR、AOS：高于整体为优（绿），低于整体为劣（红）
    case higherIsBetter
}

struct MetricDeltaCell: View {
    let value: String
    let delta: String
    let polarity: MetricDeltaPolarity

    private static let significantDeltaThresholdPercent = 10.0

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
                Text(displayDelta)
                    .font(.caption)
            }
            .foregroundStyle(deltaForegroundStyle)
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value)，相较整体 \(deltaAccessibilityDescription)")
    }

    /// 箭头已表示方向，文案仅保留幅度（如 `16%`），避免与 +/- 重复。
    private var displayDelta: String {
        if delta.hasPrefix("+") || delta.hasPrefix("-") {
            return String(delta.dropFirst())
        }
        return delta
    }

    private var deltaSymbol: String? {
        if delta.hasPrefix("+") { return "arrowtriangle.up.fill" }
        if delta.hasPrefix("-") { return "arrowtriangle.down.fill" }
        return nil
    }

    private var signedDeltaPercent: Double? {
        guard delta.hasPrefix("+") || delta.hasPrefix("-") else { return nil }
        let numeric = String(delta.dropFirst()).replacingOccurrences(of: "%", with: "")
        guard let magnitude = Double(numeric) else { return nil }
        return delta.hasPrefix("-") ? -magnitude : magnitude
    }

    private var deltaForegroundStyle: AnyShapeStyle {
        guard let signed = signedDeltaPercent else {
            return AnyShapeStyle(.secondary)
        }
        if abs(signed) <= Self.significantDeltaThresholdPercent {
            return AnyShapeStyle(.secondary)
        }
        return AnyShapeStyle(semanticDeltaColor(for: signed))
    }

    private func semanticDeltaColor(for signedPercent: Double) -> Color {
        let isAboveOverall = signedPercent > 0
        switch polarity {
        case .lowerIsBetter:
            return isAboveOverall ? .red : .green
        case .higherIsBetter:
            return isAboveOverall ? .green : .red
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
        case .highSpendHighEfficiency, .highEfficiency:
            "checkmark.circle"
        case .highSpendLowEfficiency:
            "exclamationmark.triangle"
        case .highSpend:
            "flame"
        case .lowEfficiency:
            "gauge.with.dots.needle.33percent"
        case .potentialNew:
            "sparkles"
        case .lowSampleOld:
            "hourglass"
        case .observation:
            "eye"
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .none:
            .clear
        case .lowSpend:
            Color.blue.opacity(0.15)
        case .highSpendHighEfficiency, .highEfficiency:
            Color.green.opacity(0.15)
        case .highSpendLowEfficiency:
            Color.red.opacity(0.15)
        case .highSpend:
            Color.orange.opacity(0.18)
        case .lowEfficiency:
            Color.orange.opacity(0.22)
        case .potentialNew:
            Color.teal.opacity(0.15)
        case .lowSampleOld:
            Color.blue.opacity(0.12)
        case .observation:
            Color.secondary.opacity(0.12)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .none:
            .secondary
        case .lowSpend:
            .blue
        case .highSpendHighEfficiency, .highEfficiency:
            .green
        case .highSpendLowEfficiency:
            .red
        case .highSpend:
            .orange
        case .lowEfficiency:
            .orange
        case .potentialNew:
            .teal
        case .lowSampleOld:
            .blue
        case .observation:
            .secondary
        }
    }
}
