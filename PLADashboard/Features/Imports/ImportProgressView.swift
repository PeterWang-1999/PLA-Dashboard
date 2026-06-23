import SwiftUI

struct ImportProgressView: View {
    let progress: ImportProgress

    var body: some View {
        Group {
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
        }
        .frame(minWidth: 200, idealWidth: 240, maxWidth: 280)
    }

    private var phaseTitle: String {
        switch progress.phase {
        case .staging: "准备文件"
        case .parsing: "解析文件"
        case .writing: "写入数据库"
        case .finalizing: "完成收尾"
        case .completed: "导入完成"
        case .failed: "导入失败"
        case .cancelled: "已取消"
        }
    }
}
