import SwiftUI
import UniformTypeIdentifiers

struct ImportsView: View {
    @Bindable var viewModel: ImportViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerSection

            if let result = viewModel.latestResult {
                ImportResultView(job: result.job, errors: viewModel.latestErrors)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Spacer(minLength: 0)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
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
                    ForEach(ImportSourceKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(viewModel.isImporting)
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
        case .salesReport: "自归因销售 CSV"
        case .adsProduct: "Google Ads 产品数据"
        }
    }

    private var sourceDescription: String {
        switch viewModel.selectedSourceKind {
        case .merchantCenter:
            "选择 Google Merchant Center 导出的 TSV 文件。文件将复制到应用容器并按批流式导入。"
        case .salesReport:
            "选择自归因销售明细 CSV。将写入 sales_daily，并更新 products.lsin；汇总行（LSIN = Total）自动跳过。"
        case .adsProduct:
            "选择 Google Ads 产品数据导出文件（跳过前两行标题）。将写入 ads_product_daily，费用以 micros、转化价值以 cents 存储。"
        }
    }

    private var importButtonTitle: String {
        switch viewModel.selectedSourceKind {
        case .merchantCenter: "选择 TSV 文件…"
        case .salesReport, .adsProduct: "选择 CSV 文件…"
        }
    }
}

#Preview {
    NavigationStack {
        ImportsView(viewModel: ImportViewModel())
    }
    .frame(width: 720, height: 560)
}
