import SwiftUI

struct ImportHistoryView: View {
    let jobs: [ImportJobRecord]

    private enum Metrics {
        /// macOS inset `Table` 表头近似高度（`.body` 字号）。
        static let headerHeight: CGFloat = 26
        /// macOS inset `Table` 单行近似高度（`.body` 字号）。
        static let rowHeight: CGFloat = 24
    }

    var body: some View {
        if jobs.isEmpty {
            ContentUnavailableView(
                "暂无导入记录",
                systemImage: "tray",
                description: Text("导入数据后将在此显示历史批次。")
            )
            .frame(minHeight: 160)
        } else {
            Table(jobs) {
                TableColumn("时间") { job in
                    Text(formattedDate(job.importedAt))
                        .font(.body)
                }
                .width(min: 140, ideal: 168, max: 200)

                TableColumn("数据源") { job in
                    Text(sourceDisplayName(job.sourceKind))
                        .font(.body)
                }
                .width(min: 88, ideal: 108, max: 140)

                TableColumn("文件") { job in
                    Text(job.fileName)
                        .font(.body)
                        .lineLimit(1)
                }
                .width(min: 120, ideal: 200, max: .infinity)

                TableColumn("状态") { job in
                    Label(statusLabel(job.status), systemImage: statusSymbol(job.status))
                        .font(.body)
                        .foregroundStyle(statusForegroundStyle(job.status))
                }
                .width(min: 72, ideal: 96, max: 120)

                TableColumn("有效/总计") { job in
                    Text("\(job.validRows) / \(job.totalRows)")
                        .font(.body)
                }
                .width(min: 72, ideal: 88, max: 100)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .scrollDisabled(true)
            .frame(
                maxWidth: .infinity,
                minHeight: tableHeight,
                maxHeight: tableHeight,
                alignment: .topLeading
            )
        }
    }

    private var tableHeight: CGFloat {
        Metrics.headerHeight + Metrics.rowHeight * CGFloat(jobs.count)
    }

    private func sourceDisplayName(_ raw: String) -> String {
        ImportSourceKind(rawValue: raw)?.displayName ?? raw
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

    private func statusSymbol(_ status: String) -> String {
        switch ImportJobStatus(rawValue: status) {
        case .running: "clock"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .cancelled: "minus.circle.fill"
        case .none: "questionmark.circle"
        }
    }

    private func statusForegroundStyle(_ status: String) -> AnyShapeStyle {
        switch ImportJobStatus(rawValue: status) {
        case .succeeded, .failed, .cancelled, .running:
            AnyShapeStyle(.primary)
        case .none:
            AnyShapeStyle(.secondary)
        }
    }
}
