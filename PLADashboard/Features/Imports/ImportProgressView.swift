import SwiftUI

struct ImportProgressView: View {
    let progress: ImportProgress

    var body: some View {
        Group {
            if let fraction = progress.fractionCompleted {
                ProgressView(value: fraction) {
                    progressLabel
                } currentValueLabel: {
                    rowCountLabel
                }
            } else {
                ProgressView {
                    progressLabel
                }
            }
        }
        .frame(minWidth: 200, idealWidth: 260, maxWidth: 300)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var progressLabel: some View {
        if progress.showsDeterminateRowProgress {
            Text(phaseTitle)
                .font(.subheadline)
        } else {
            Text(progress.message ?? phaseTitle)
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private var rowCountLabel: some View {
        if progress.showsDeterminateRowProgress, let total = progress.totalRowsEstimate {
            Text("\(formattedCount(progress.processedRows)) / \(formattedCount(total))")
                .monospacedDigit()
        } else if progress.processedRows > 0 {
            Text(formattedCount(progress.processedRows))
                .monospacedDigit()
        }
    }

    private var accessibilitySummary: String {
        if progress.showsDeterminateRowProgress, let total = progress.totalRowsEstimate {
            return "\(phaseTitle)，已处理 \(progress.processedRows) 行，共 \(total) 行"
        }
        if let message = progress.message {
            return message
        }
        return phaseTitle
    }

    private func formattedCount(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
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
