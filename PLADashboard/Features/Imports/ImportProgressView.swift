import SwiftUI

struct ImportProgressView: View {
    let progress: ImportProgress

    var body: some View {
        Group {
            if let fraction = progress.fractionCompleted {
                ProgressView(value: fraction) {
                    progressLabel
                } currentValueLabel: {
                    Text("\(progress.processedRows)")
                        .monospacedDigit()
                }
            } else {
                ProgressView {
                    progressLabel
                }
            }
        }
        .frame(minWidth: 200, idealWidth: 240, maxWidth: 280)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var progressLabel: some View {
        Text(progress.message ?? phaseTitle)
            .font(.subheadline)
    }

    private var accessibilitySummary: String {
        if let message = progress.message {
            return message
        }
        return phaseTitle
    }

    private var phaseTitle: String {
        switch progress.phase {
        case .staging: "准备文件"
        case .parsing: "解析文件"
        case .writing: "写入数据库"
        case .indexing: "更新搜索索引"
        case .rebuildingCatalogs: "更新筛选目录"
        case .rebuildingMetrics: "重建周聚合"
        case .refreshingDashboard: "刷新看板"
        case .finalizing: "完成收尾"
        case .completed: "导入完成"
        case .failed: "导入失败"
        case .cancelled: "已取消"
        }
    }
}
