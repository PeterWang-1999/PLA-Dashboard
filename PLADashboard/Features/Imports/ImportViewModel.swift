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
    var isLoadingImportErrors = false
    var errorMessage: String?
    var isImporting = false

    private(set) var availableImportKinds: [ImportSourceKind] = WorkspaceCapabilities
        .forKind(.thirdParty).importSourceKinds

    private var databaseClient: DatabaseClient?
    private var accountKind: WorkspaceAccountKind = .thirdParty
    private var importTask: Task<Void, Never>?
    private var onReloadFilterCatalogs: (@Sendable () async -> Void)?
    private var onImportCompleted: (@Sendable () async -> Void)?

    func configure(
        databaseClient: DatabaseClient,
        capabilities: WorkspaceCapabilities,
        accountKind: WorkspaceAccountKind,
        onReloadFilterCatalogs: @escaping @Sendable () async -> Void,
        onImportCompleted: @escaping @Sendable () async -> Void
    ) {
        self.databaseClient = databaseClient
        self.accountKind = accountKind
        self.onReloadFilterCatalogs = onReloadFilterCatalogs
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
        importTask?.cancel()
        importTask = nil
        latestResult = nil
        latestErrors = []
        isLoadingImportErrors = false
        importJobs = []
        errorMessage = nil
        progress = nil
        isImporting = false
        showFileImporter = false
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
        let resourceName = selectedSourceKind.sampleResourceName(accountKind: accountKind)
        guard let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: selectedSourceKind.sampleFileExtension
        ) else {
            errorMessage = "未找到内置样例文件 \(resourceName).\(selectedSourceKind.sampleFileExtension)"
            return
        }
        startImport(
            at: url,
            fileName: "\(resourceName).\(selectedSourceKind.sampleFileExtension)"
        )
    }

    private func startImport(at url: URL, fileName: String? = nil) {
        guard let databaseClient else {
            errorMessage = "数据库未就绪"
            return
        }

        importTask?.cancel()
        let sourceKind = selectedSourceKind
        let accountKind = accountKind
        let reloadFilterCatalogs = onReloadFilterCatalogs
        let importCompleted = onImportCompleted
        let securityScopedAccess = url.startAccessingSecurityScopedResource()

        importTask = Task.detached(priority: .userInitiated) { [weak self] in
            defer {
                if securityScopedAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            await MainActor.run {
                guard let self else { return }
                self.isImporting = true
                self.errorMessage = nil
                self.latestResult = nil
                self.latestErrors = []
                self.isLoadingImportErrors = false
                self.progress = nil
            }

            do {
                let result = try await ImportPipelineRunner.importFile(
                    sourceKind: sourceKind,
                    sourceURL: url,
                    fileName: fileName,
                    databaseClient: databaseClient,
                    accountKind: accountKind,
                    onProgress: { update in
                        await MainActor.run { [weak self] in
                            self?.progress = update
                        }
                    }
                )

                try Task.checkCancellation()

                let shouldLoadErrors = result.job.invalidRows > 0 || result.job.warningRows > 0
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.latestResult = ImportResult(
                        importId: result.importId,
                        stagedFileURL: result.stagedFileURL,
                        job: result.job,
                        errors: []
                    )
                    self.latestErrors = []
                    self.isLoadingImportErrors = shouldLoadErrors
                }

                try await ImportPipelineRunner.finishImport(
                    sourceKind: sourceKind,
                    result: result,
                    databaseClient: databaseClient,
                    accountKind: accountKind,
                    onProgress: { update in
                        await MainActor.run { [weak self] in
                            self?.progress = update
                        }
                    },
                    reloadFilterCatalogs: {
                        if let reloadFilterCatalogs {
                            await reloadFilterCatalogs()
                        }
                    },
                    refreshDashboard: {
                        if let importCompleted {
                            await importCompleted()
                        }
                    }
                )

                try Task.checkCancellation()

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.latestErrors = result.errors
                    self.isLoadingImportErrors = false
                    self.isImporting = false
                    self.progress = nil
                }
                await self?.loadHistory()
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isImporting = false
                    self.isLoadingImportErrors = false
                    self.progress = nil
                    self.errorMessage = nil
                }
                await self?.loadHistory()
            } catch let pipelineError as ImportPipelineError {
                if case .duplicateFile = pipelineError, sourceKind == .merchantCenter {
                    let importer = MerchantCenterImporter(
                        databaseClient: databaseClient,
                        accountKind: accountKind
                    )
                    _ = try? await importer.refreshProductCategories(sourceURL: url)
                    if let reloadFilterCatalogs {
                        await reloadFilterCatalogs()
                    }
                    if let importCompleted {
                        await importCompleted()
                    }
                }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.errorMessage = ImportUserFacingError.message(for: pipelineError)
                    self.isImporting = false
                    self.isLoadingImportErrors = false
                    self.progress = nil
                }
                await self?.loadHistory()
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.errorMessage = ImportUserFacingError.message(for: error)
                    self.isImporting = false
                    self.isLoadingImportErrors = false
                    self.progress = nil
                }
                await self?.loadHistory()
            }
        }
    }
}
