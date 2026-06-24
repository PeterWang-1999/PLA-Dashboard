import Foundation
import Observation

@MainActor
@Observable
final class ImportViewModel {
    var selectedSourceKind: ImportSourceKind = .merchantCenter
    var showFileImporter = false
    var importJobs: [ImportJobRecord] = []
    var progress: ImportProgress?
    var latestResult: ImportResult?
    var latestErrors: [ImportRowErrorRecord] = []
    var errorMessage: String?
    var isImporting = false

    private var databaseClient: DatabaseClient?
    private var importTask: Task<Void, Never>?
    private var onCatalogReload: ((URL) -> Void)?
    private var onImportCompleted: (() async -> Void)?

    func configure(
        databaseClient: DatabaseClient,
        onCatalogReload: @escaping (URL) -> Void,
        onImportCompleted: @escaping () async -> Void
    ) {
        self.databaseClient = databaseClient
        self.onCatalogReload = onCatalogReload
        self.onImportCompleted = onImportCompleted
        if !ImportSourceKind.importPickerCases.contains(selectedSourceKind) {
            selectedSourceKind = .merchantCenter
        }
    }

    func presentImportPicker() {
        showFileImporter = true
    }

    func cancelImport() {
        importTask?.cancel()
    }

    func clearError() {
        errorMessage = nil
    }

    func loadHistory() async {
        guard let databaseClient else { return }
        do {
            importJobs = try await databaseClient.fetchImportJobs()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handleImportedURLs(_ urls: [URL]) {
        guard let url = urls.first else { return }
        startImport(at: url)
    }

    func importSampleFile() {
        guard let url = Bundle.main.url(
            forResource: selectedSourceKind.sampleResourceName,
            withExtension: selectedSourceKind.sampleFileExtension
        ) else {
            errorMessage = "未找到内置样例文件 \(selectedSourceKind.sampleResourceName).\(selectedSourceKind.sampleFileExtension)"
            return
        }
        startImport(
            at: url,
            fileName: "\(selectedSourceKind.sampleResourceName).\(selectedSourceKind.sampleFileExtension)"
        )
    }

    private func startImport(at url: URL, fileName: String? = nil) {
        guard let databaseClient else {
            errorMessage = "数据库未就绪"
            return
        }

        importTask?.cancel()
        let sourceKind = selectedSourceKind
        let catalogReload = onCatalogReload
        let importCompleted = onImportCompleted

        importTask = Task {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            await MainActor.run {
                isImporting = true
                errorMessage = nil
                latestResult = nil
                latestErrors = []
                progress = nil
            }

            do {
                let result = try await ImportPipelineRunner.importFile(
                    sourceKind: sourceKind,
                    sourceURL: url,
                    fileName: fileName,
                    databaseClient: databaseClient,
                    onProgress: { update in
                        await MainActor.run { [weak self] in
                            self?.progress = update
                        }
                    }
                )

                try Task.checkCancellation()

                await MainActor.run {
                    latestResult = result
                    latestErrors = result.errors
                    progress = ImportProgress(
                        phase: .finalizing,
                        processedRows: result.job.totalRows,
                        totalRowsEstimate: result.job.totalRows,
                        validRows: result.job.validRows,
                        invalidRows: result.job.invalidRows,
                        warningRows: result.job.warningRows,
                        message: "正在重建周聚合…"
                    )
                }

                if sourceKind == .merchantCenter {
                    catalogReload?(result.stagedFileURL)
                }

                try await ImportPipelineRunner.rebuildWeeklyMetrics(databaseClient: databaseClient)
                await importCompleted?()

                await MainActor.run {
                    isImporting = false
                    progress = nil
                }
                await loadHistory()
            } catch is CancellationError {
                await MainActor.run {
                    isImporting = false
                    progress = nil
                    errorMessage = nil
                }
                await loadHistory()
            } catch let pipelineError as ImportPipelineError {
                await MainActor.run {
                    errorMessage = pipelineError.localizedDescription
                    isImporting = false
                    progress = nil
                }
                await loadHistory()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isImporting = false
                    progress = nil
                }
                await loadHistory()
            }
        }
    }
}
