import SwiftUI
import UniformTypeIdentifiers

struct ImportResultView: View {
    let job: ImportJobRecord
    let errors: [ImportRowErrorRecord]
    var isLoadingErrors: Bool = false

    @State private var isExportingErrors = false
    @State private var exportDocument = ImportErrorsCSVDocument(errors: [])

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                if job.invalidRows > 0 || job.warningRows > 0 || !errors.isEmpty {
                    Text("错误与警告（最多显示 200 条）")
                        .font(.headline)
                }

                Spacer()

                HStack(spacing: 16) {
                    summaryItem(title: "总行数", value: "\(job.totalRows)")
                    summaryItem(
                        title: "有效",
                        value: "\(job.validRows)",
                        symbol: "checkmark.circle"
                    )
                    summaryItem(
                        title: "错误",
                        value: "\(job.invalidRows)",
                        symbol: job.invalidRows > 0 ? "xmark.circle" : nil
                    )
                    summaryItem(
                        title: "警告",
                        value: "\(job.warningRows)",
                        symbol: job.warningRows > 0 ? "exclamationmark.triangle" : nil
                    )
                }
            }

            if isLoadingErrors {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在加载错误与警告…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("正在加载错误与警告")
            } else if !errors.isEmpty {
                HStack {
                    Spacer()
                    Button("导出错误与警告…") {
                        exportDocument = ImportErrorsCSVDocument(errors: errors)
                        isExportingErrors = true
                    }
                    .buttonStyle(.bordered)
                }

                Table(errors) {
                    TableColumn("行号") { error in
                        Text("\(error.rowNumber)")
                            .font(.body)
                    }
                    .width(min: 48, ideal: 56, max: 64)

                    TableColumn("级别") { error in
                        Label {
                            Text(error.severity)
                                .font(.body)
                        } icon: {
                            Image(systemName: severitySymbol(error.severity))
                        }
                        .foregroundStyle(.primary)
                    }
                    .width(min: 56, ideal: 72, max: 88)

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
        .fileExporter(
            isPresented: $isExportingErrors,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "import-errors-\(job.id)"
        ) { _ in }
    }

    private func severitySymbol(_ severity: String) -> String {
        severity == ImportRowSeverity.error.rawValue
            ? "xmark.circle.fill"
            : "exclamationmark.triangle.fill"
    }

    private func summaryItem(title: String, value: String, symbol: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let symbol {
                Label(value, systemImage: symbol)
                    .font(.title3.weight(.semibold))
            } else {
                Text(value)
                    .font(.title3.weight(.semibold))
            }
        }
    }
}

struct ImportErrorsCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    let text: String

    init(errors: [ImportRowErrorRecord]) {
        var lines = ["row_number,severity,field_name,message"]
        lines.reserveCapacity(errors.count + 1)
        for error in errors {
            let field = error.fieldName ?? ""
            lines.append(
                "\(error.rowNumber),\(Self.escapeCSV(error.severity)),\(Self.escapeCSV(field)),\(Self.escapeCSV(error.message))"
            )
        }
        text = lines.joined(separator: "\n")
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }

    private static func escapeCSV(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
