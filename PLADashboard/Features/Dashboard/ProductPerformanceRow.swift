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
