import SwiftUI

struct ImportResultView: View {
    let job: ImportJobRecord
    let errors: [ImportRowErrorRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                if !errors.isEmpty {
                    Text("错误与警告（最多显示 200 条）")
                        .font(.headline)
                }

                Spacer()

                HStack(spacing: 16) {
                    summaryItem(title: "总行数", value: "\(job.totalRows)")
                    summaryItem(title: "有效", value: "\(job.validRows)")
                    summaryItem(title: "错误", value: "\(job.invalidRows)", color: job.invalidRows > 0 ? .red : .secondary)
                    summaryItem(title: "警告", value: "\(job.warningRows)", color: job.warningRows > 0 ? .orange : .secondary)
                }
            }

            if !errors.isEmpty {
                Table(errors) {
                    TableColumn("行号") { error in
                        Text("\(error.rowNumber)")
                            .font(.body)
                    }
                    .width(min: 48, ideal: 56, max: 64)

                    TableColumn("级别") { error in
                        Text(error.severity)
                            .font(.body)
                            .foregroundStyle(error.severity == ImportRowSeverity.error.rawValue ? .red : .orange)
                    }
                    .width(min: 48, ideal: 56, max: 72)

                    TableColumn("字段") { error in
                        Text(error.fieldName ?? "—")
                            .font(.body)
                    }
                    .width(min: 56, ideal: 80, max: 120)

                    TableColumn("说明") { error in
                        Text(error.message)
                            .font(.body)
                            .lineLimit(2)
                    }
                    .width(min: 120, ideal: 200, max: .infinity)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .frame(minHeight: 150, maxHeight: 300)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryItem(title: String, value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
        }
    }
}
