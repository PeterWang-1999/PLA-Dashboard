import SwiftUI

struct ImportProgressView: View {
    let progress: ImportProgress
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let fraction = progress.fractionCompleted {
                ProgressView(value: fraction) {
                    Text(progress.message ?? phaseTitle)
                } currentValueLabel: {
                    Text("\(progress.processedRows)")
                }
            } else {
                ProgressView {
                    Text(progress.message ?? phaseTitle)
                }
            }

            HStack(spacing: 16) {
                Text("有效 \(progress.validRows)")
                Text("错误 \(progress.invalidRows)")
                    .foregroundStyle(progress.invalidRows > 0 ? .red : .secondary)
                Text("警告 \(progress.warningRows)")
                    .foregroundStyle(progress.warningRows > 0 ? .orange : .secondary)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            Button("取消导入", role: .cancel, action: onCancel)
                .disabled(progress.phase == .completed || progress.phase == .failed || progress.phase == .cancelled)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var phaseTitle: String {
        switch progress.phase {
        case .staging: "准备文件"
        case .parsing: "解析 TSV"
        case .writing: "写入数据库"
        case .finalizing: "完成收尾"
        case .completed: "导入完成"
        case .failed: "导入失败"
        case .cancelled: "已取消"
        }
    }
}
