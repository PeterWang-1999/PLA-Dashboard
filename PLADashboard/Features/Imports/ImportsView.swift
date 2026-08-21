import SwiftUI

struct ImportsView: View {
    @Bindable var viewModel: ImportViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerSection

            if let result = viewModel.latestResult {
                ImportResultView(
                    job: result.job,
                    errors: viewModel.latestErrors,
                    isLoadingErrors: viewModel.isLoadingImportErrors
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Spacer(minLength: 0)
            }

            historySection
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("数据导入")
        .alert(viewModel.importAlertTitle, isPresented: importErrorAlertPresented) {
            Button("好", role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
    }

    private var importErrorAlertPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.clearError()
                }
            }
        )
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
                    ForEach(viewModel.availableImportKinds) { kind in
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
        case .plaDeliveryDetail: "投放产品明细"
        case .salesReport: "Product Sales CSV"
        }
    }

    private var sourceDescription: String {
        switch viewModel.selectedSourceKind {
        case .merchantCenter:
            "选择 Google Merchant Center 导出的 TSV 文件。文件将复制到应用容器并按批流式导入。"
        case .adsProduct:
            "选择 Google Ads 产品数据导出文件。应用会自动识别前 10 行内的表头；消费与「销售趋势」来自 Ads 费用、转化价值等字段。"
        case .plaDeliveryDetail:
            "选择投放产品明细导出文件（CSV 或 XLSX，第 1 行为表头）。将写入 ads_product_daily；消费与「销售趋势」来自 Conversion Value 等字段。"
        case .salesReport:
            "选择 Product Sales CSV 文件（需含 Gross Sales($) 与 毛利额($)）。将写入 sales_daily；看板「销售趋势」列仍来自投放明细转化价值，不会自动切换为 Gross Sales。"
        }
    }

    private var importButtonTitle: String {
        switch viewModel.selectedSourceKind {
        case .merchantCenter: "选择 TSV 文件…"
        case .adsProduct: "选择 CSV 文件…"
        case .plaDeliveryDetail: "选择 CSV / XLSX 文件…"
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
