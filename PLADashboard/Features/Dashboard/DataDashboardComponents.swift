import SwiftUI

struct SectionHeader: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

extension View {
    /// 使用系统语义颜色建立卡片层级，自动适配浅色、深色与辅助功能外观。
    func cardSurface(cornerRadius: CGFloat) -> some View {
        background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 2)
    }
}

struct DataDashboardMetricCard: View {
    let metric: DataDashboardMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Text(metric.reference)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text(metric.value)
                .font(.system(.largeTitle, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            HStack(spacing: 6) {
                if metric.comparisonDirection != .neutral {
                    Image(systemName: comparisonSymbol)
                        .accessibilityHidden(true)
                }
                Text(metric.comparison)
                    .monospacedDigit()
                Text(metric.comparisonLabel)
                    .fontWeight(.regular)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(comparisonColor)
        }
        .padding(16)
        .cardSurface(cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }

    private var comparisonSymbol: String {
        switch metric.comparisonDirection {
        case .positive: "arrowtriangle.up.fill"
        case .negative: "arrowtriangle.down.fill"
        case .neutral: "minus"
        }
    }

    private var comparisonColor: Color {
        switch metric.comparisonDirection {
        case .positive: .green
        case .negative: .red
        case .neutral: .secondary
        }
    }
}

struct CampaignPerformanceList: View {
    let rows: [DataDashboardCampaignRow]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
            GridRow {
                Text("广告系列").gridColumnAlignment(.leading)
                Text("消费").gridColumnAlignment(.trailing)
                Text("ROI").gridColumnAlignment(.trailing)
                Text("CPC").gridColumnAlignment(.trailing)
                Text("CVR").gridColumnAlignment(.trailing)
                Text("AOS").gridColumnAlignment(.trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.vertical, 10)

            Divider().gridCellColumns(6)
            ForEach(rows) { row in
                GridRow {
                    Text(row.campaign).lineLimit(1).help(row.campaign)
                    Text(Double(row.metrics.costCents) / 100, format: .currency(code: "USD").precision(.fractionLength(2)))
                    Text(row.metrics.roi, format: .number.precision(.fractionLength(2)))
                    Text(row.metrics.cpc, format: .currency(code: "USD").precision(.fractionLength(2)))
                    Text(row.metrics.cvr, format: .percent.precision(.fractionLength(2)))
                    Text(row.metrics.aos, format: .currency(code: "USD").precision(.fractionLength(2)))
                }
                .monospacedDigit()
                .padding(.vertical, 9)
                Divider().gridCellColumns(6)
            }
        }
        .padding(.horizontal, 14)
        .cardSurface(cornerRadius: 14)
        .accessibilityElement(children: .contain)
    }
}

struct TopProductCard: View {
    let rank: Int
    let product: DataDashboardProduct

    var body: some View {
        HStack(spacing: 12) {
            ProductImageView(imageURL: product.imageURL, size: 72)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(product.title).font(.headline).lineLimit(1)
                    Spacer()
                    Text("#\(rank)").font(.caption.weight(.semibold)).foregroundStyle(.tint)
                }
                Text(product.productID).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                    GridRow { Text("消费").foregroundStyle(.secondary); Text(Double(product.metrics.costCents) / 100, format: .currency(code: "USD")) }
                    GridRow { Text("销售").foregroundStyle(.secondary); Text(Double(product.metrics.conversionValueCents) / 100, format: .currency(code: "USD")) }
                    GridRow { Text("ROI").foregroundStyle(.secondary); Text(product.metrics.roi, format: .number.precision(.fractionLength(2))) }
                }
                .font(.caption)
                .monospacedDigit()
            }
        }
        .padding(12)
        .cardSurface(cornerRadius: 14)
        .accessibilityElement(children: .combine)
    }
}
