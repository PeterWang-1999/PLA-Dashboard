import SwiftUI

struct ImportHistoryView: View {
    let jobs: [ImportJobRecord]

    var body: some View {
        if jobs.isEmpty {
            ContentUnavailableView(
                "暂无导入记录",
                systemImage: "tray",
                description: Text("导入 Merchant Center TSV 后将在此显示历史批次。")
            )
            .frame(minHeight: 160)
        } else {
            Table(jobs) {
                TableColumn("时间") { job in
                    Text(formattedDate(job.importedAt))
                        .font(.system(size: 13))
                }
                .width(min: 140, ideal: 168, max: 200)

                TableColumn("文件") { job in
                    Text(job.fileName)
                        .font(.system(size: 13))
                        .lineLimit(1)
                }
                .width(min: 120, ideal: 200, max: .infinity)

                TableColumn("状态") { job in
                    Text(statusLabel(job.status))
                        .font(.system(size: 13))
                        .foregroundStyle(statusColor(job.status))
                }
                .width(min: 56, ideal: 72, max: 88)

                TableColumn("有效/总计") { job in
                    Text("\(job.validRows) / \(job.totalRows)")
                        .font(.system(size: 13))
                }
                .width(min: 72, ideal: 88, max: 100)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .frame(minHeight: 180)
        }
    }

    private func formattedDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func statusLabel(_ status: String) -> String {
        switch ImportJobStatus(rawValue: status) {
        case .running: "进行中"
        case .succeeded: "成功"
        case .failed: "失败"
        case .cancelled: "已取消"
        case .none: status
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch ImportJobStatus(rawValue: status) {
        case .succeeded: .green
        case .failed: .red
        case .cancelled: .orange
        case .running: .blue
        case .none: .secondary
        }
    }
}
