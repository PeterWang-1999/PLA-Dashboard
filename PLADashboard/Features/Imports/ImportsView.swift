import SwiftUI
import UniformTypeIdentifiers

struct ImportsView: View {
    @Bindable var viewModel: ImportViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                if viewModel.isImporting, let progress = viewModel.progress {
                    ImportProgressView(progress: progress) {
                        viewModel.cancelImport()
                    }
                }

                if let result = viewModel.latestResult {
                    ImportResultView(job: result.job, errors: viewModel.latestErrors)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("导入历史")
                        .font(.headline)
                    ImportHistoryView(jobs: viewModel.importJobs)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("数据导入")
        .task {
            await viewModel.loadHistory()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Merchant Center TSV")
                .font(.title2.weight(.semibold))
            Text("选择 Google Merchant Center 导出的 TSV 文件。文件将复制到应用容器并按批流式导入。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    viewModel.presentImportPicker()
                } label: {
                    Label("选择 TSV 文件…", systemImage: "doc.badge.plus")
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
    }
}

#Preview {
    NavigationStack {
        ImportsView(viewModel: ImportViewModel())
    }
    .frame(width: 720, height: 560)
}
