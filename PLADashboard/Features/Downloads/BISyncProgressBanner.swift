import SwiftUI

struct BISyncProgressBanner: View {
    let phase: BIDownloadStore.SyncPhase
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("同步投放产品明细")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.updatesFrequently)
                if let fraction {
                    ProgressView(value: fraction)
                        .accessibilityLabel("导入进度")
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .accessibilityLabel("同步进行中")
                }
            }
            .frame(maxWidth: 340, alignment: .leading)

            Spacer(minLength: 0)

            if phase.canCancel {
                Button("取消同步", action: onCancel)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.accentColor.opacity(0.1))
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
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
