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

    private(set) var availableImportKinds: [ImportSourceKind] = WorkspaceCapabilities
        .forKind(.thirdParty).importSourceKinds

    private var databaseClient: DatabaseClient?
    private var importTask: Task<Void, Never>?
    private var onCatalogReload: ((URL) -> Void)?
    private var onImportCompleted: (() async -> Void)?

    func configure(
        databaseClient: DatabaseClient,
        capabilities: WorkspaceCapabilities,
        onCatalogReload: @escaping (URL) -> Void,
        onImportCompleted: @escaping () async -> Void
    ) {
        self.databaseClient = databaseClient
        self.onCatalogReload = onCatalogReload
        self.onImportCompleted = onImportCompleted
        applyCapabilities(capabilities)
    }

    func applyCapabilities(_ capabilities: WorkspaceCapabilities) {
        availableImportKinds = capabilities.importSourceKinds
        if !availableImportKinds.contains(selectedSourceKind) {
            selectedSourceKind = availableImportKinds.first ?? .merchantCenter
        }
    }

    func resetForAccountSwitch() {
        latestResult = nil
        latestErrors = []
        importJobs = []
        errorMessage = nil
        progress = nil
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

    var importAlertTitle: String {
        guard let errorMessage else { return "导入失败" }
        if errorMessage.contains("已导入过") || errorMessage.contains("已取消") {
            return "导入未继续"
        }
        return "导入失败"
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
