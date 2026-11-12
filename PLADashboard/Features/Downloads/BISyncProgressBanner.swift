import SwiftUI

struct BISyncProgressBanner: View {
    let phase: BIDownloadStore.SyncPhase
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("同步投放产品明细")
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
                .accessibilityLabel("导入进度")
        } else {
            ProgressView()
                .accessibilityLabel("同步进行中")
        }
    }

    private var status: String {
        switch phase {
        case .connecting:
            "正在连接 BI Data…"
        case let .downloading(file, total):
            "正在下载报表（\(file)/\(total)）…"
        case let .importing(progress):
            progress.message ?? "正在导入，已处理 \(progress.processedRows) 行…"
        case let .finishing(message):
            message
        case .cancelling:
            "正在取消同步…"
        }
    }

    private var fraction: Double? {
        guard case let .importing(progress) = phase else { return nil }
        return progress.fractionCompleted
    }
}
