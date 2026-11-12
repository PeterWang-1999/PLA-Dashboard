import SwiftUI

struct BISyncProgressBanner: View {
    let phase: BIDownloadStore.SyncPhase
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("同步 BI 数据")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if phase.canCancel {
                    Button("取消同步", action: onCancel)
                        .buttonStyle(.bordered)
                        .fixedSize()
                }
            }
            progressBar
                .progressViewStyle(.linear)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.accentColor.opacity(0.1))
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var progressBar: some View {
        if let fraction {
            ProgressView(value: fraction)
                .accessibilityLabel("当前阶段进度")
        } else {
            ProgressView()
                .accessibilityLabel("同步进行中")
        }
    }

    private var status: String {
        switch phase {
        case .connecting:
            return "正在连接 BI Data…"
        case let .downloading(completed, total):
            return "正在获取 BI Data 报表，已下载 \(completed) / \(total) 份…"
        case let .importing(report, progress):
            return "\(report.rawValue) · \(progress.message ?? "正在导入，已处理 \(progress.processedRows) 行…")"
        case let .finishing(message):
            return message
        case .cancelling:
            return "正在取消同步…"
        }
    }

    private var fraction: Double? {
        switch phase {
        case let .downloading(completed, total) where total > 0:
            return Double(completed) / Double(total)
        case let .importing(_, progress):
            return progress.fractionCompleted
        default:
            return nil
        }
    }
}
