import SwiftUI

struct ImportsView: View {
    @Bindable var viewModel: ImportViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerSection

            if let errorMessage = viewModel.errorMessage {
                importErrorBanner(message: errorMessage)
            }

            if let result = viewModel.latestResult {
                ImportResultView(job: result.job, errors: viewModel.latestErrors)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if viewModel.errorMessage == nil {
                Spacer(minLength: 0)
            }

            historySection
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("数据导入")
        .task {
            await viewModel.loadHistory()
        }
    }

    private func importErrorBanner(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(message)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
            }

            Button("关闭") {
                viewModel.clearError()
            }
            .buttonStyle(.link)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("导入失败：\(message)")
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("导入历史")
                .font(.headline)
            ImportHistoryView(jobs: ImportJobRecord.latestPerSourceKind(from: viewModel.importJobs))
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(sourceTitle)
                    .font(.title2.weight(.semibold))
                Spacer()
                Picker("数据源", selection: $viewModel.selectedSourceKind) {
                    ForEach(ImportSourceKind.importPickerCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(viewModel.isImporting)
                .accessibilityLabel("数据源")
                .accessibilityValue(viewModel.selectedSourceKind.displayName)
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(sourceDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            viewModel.presentImportPicker()
                        } label: {
                            Label(importButtonTitle, systemImage: "doc.badge.plus")
                        }
                        .disabled(viewModel.isImporting)

                        Button {
                            viewModel.importSampleFile()
                        } label: {
                            Label("导入样例文件", systemImage: "doc.text")
                        }
                        .disabled(viewModel.isImporting)

                        if viewModel.isImporting {
                            Button("取消导入", role: .cancel) {
                                viewModel.cancelImport()
                            }
                            .keyboardShortcut(.cancelAction)
                        }
                    }
                    .controlSize(.large)
                }

                Spacer()

                if viewModel.isImporting, let progress = viewModel.progress {
                    ImportProgressView(progress: progress)
                }
            }
        }
    }

    private var sourceTitle: String {
        switch viewModel.selectedSourceKind {
        case .merchantCenter: "Merchant Center TSV"
        case .adsProduct: "Google Ads 产品数据"
        case .salesReport: "自归因销售 CSV"
        }
    }

    private var sourceDescription: String {
        switch viewModel.selectedSourceKind {
        case .merchantCenter:
            "选择 Google Merchant Center 导出的 TSV 文件。文件将复制到应用容器并按批流式导入。"
        case .adsProduct:
            "选择 Google Ads 产品数据导出文件（跳过前两行标题）。将写入 ads_product_daily；消费与「销售趋势」均来自 Ads 转化价值等字段。"
        case .salesReport:
            ""
        }
    }

    private var importButtonTitle: String {
        switch viewModel.selectedSourceKind {
        case .merchantCenter: "选择 TSV 文件…"
        case .adsProduct: "选择 CSV 文件…"
        case .salesReport: "选择 CSV 文件…"
        }
    }
}

#Preview {
    NavigationStack {
        ImportsView(viewModel: ImportViewModel())
    }
    .frame(width: 720, height: 560)
}
