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
    private var accountStore: AccountStore?
    private var configuredWorkspaceRevision: UInt = 0
    private var loadGeneration: UInt = 0
    private var activeOperationID: UUID?
    private var onReloadFilterCatalogs: (@Sendable () async -> Void)?
    private var onImportCompleted: (@Sendable () async -> Void)?

    func configure(
        databaseClient: DatabaseClient,
        accountStore: AccountStore,
        capabilities: WorkspaceCapabilities,
        accountKind: WorkspaceAccountKind,
        onReloadFilterCatalogs: @escaping @Sendable () async -> Void,
        onImportCompleted: @escaping @Sendable () async -> Void
    ) {
        self.databaseClient = databaseClient
        self.accountStore = accountStore
        configuredWorkspaceRevision = accountStore.workspaceRevision
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
        loadGeneration &+= 1
        activeOperationID = nil
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
        let generation = loadGeneration
        guard let databaseClient else { return }
        do {
            let jobs = try await databaseClient.fetchImportJobs()
            guard generation == loadGeneration else { return }
            importJobs = jobs
        } catch {
            guard generation == loadGeneration else { return }
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
        guard let databaseClient, let accountStore else {
            errorMessage = "数据库未就绪"
            return
        }

        let operationID: UUID
        do {
            operationID = try accountStore.beginImport(
                accountID: databaseClient.accountID,
                workspaceRevision: configuredWorkspaceRevision
            )
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        activeOperationID = operationID
        isImporting = true
        errorMessage = nil
        latestResult = nil
        latestErrors = []
        isLoadingImportErrors = false
        progress = nil
        let sourceKind = selectedSourceKind
        let accountKind = accountKind
        let reloadFilterCatalogs = onReloadFilterCatalogs
        let importCompleted = onImportCompleted
        let securityScopedAccess = url.startAccessingSecurityScopedResource()

        importTask = Task(priority: .userInitiated) { [weak self] in
            defer {
                accountStore.endImport(operationID)
                if securityScopedAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            guard let self else { return }
            defer {
                if self.activeOperationID == operationID {
                    self.activeOperationID = nil
                    self.importTask = nil
                    self.isImporting = false
                    self.isLoadingImportErrors = false
                    self.progress = nil
                }
            }

            do {
                let result = try await ImportPipelineRunner.importFile(
                    sourceKind: sourceKind,
                    sourceURL: url,
                    fileName: fileName,
                    databaseClient: databaseClient,
                    accountKind: accountKind,
                    onProgress: { update in
                        await self.updateProgress(update, operationID: operationID)
                    }
                )

                try Task.checkCancellation()
                guard self.isCurrentOperation(operationID) else { return }

                let shouldLoadErrors = result.job.invalidRows > 0 || result.job.warningRows > 0
                self.latestResult = ImportResult(
                    importId: result.importId,
                    stagedFileURL: result.stagedFileURL,
                    job: result.job,
                    errors: []
                )
                self.latestErrors = []
                self.isLoadingImportErrors = shouldLoadErrors

                try await ImportPipelineRunner.finishImport(
                    sourceKind: sourceKind,
                    result: result,
                    databaseClient: databaseClient,
                    accountKind: accountKind,
                    onProgress: { update in
                        await self.updateProgress(update, operationID: operationID)
                    },
                    reloadFilterCatalogs: {
                        guard await self.isCurrentOperation(operationID), !Task.isCancelled else { return }
                        if let reloadFilterCatalogs {
                            await reloadFilterCatalogs()
                        }
                    },
                    refreshDashboard: {
                        guard await self.isCurrentOperation(operationID), !Task.isCancelled else { return }
                        if let importCompleted {
                            await importCompleted()
                        }
                    }
                )

                try Task.checkCancellation()
                guard self.isCurrentOperation(operationID) else { return }

                self.latestErrors = result.errors
                await self.loadHistory()
            } catch is CancellationError {
                guard self.isCurrentOperation(operationID) else { return }
                self.errorMessage = nil
                await self.loadHistory()
            } catch let pipelineError as ImportPipelineError {
                guard self.isCurrentOperation(operationID) else { return }
                if case .duplicateFile = pipelineError, sourceKind == .merchantCenter {
                    let importer = MerchantCenterImporter(
                        databaseClient: databaseClient,
                        accountKind: accountKind
                    )
                    _ = try? await importer.refreshProductCategories(sourceURL: url)
                    guard self.isCurrentOperation(operationID), !Task.isCancelled else { return }
                    if let reloadFilterCatalogs {
                        await reloadFilterCatalogs()
                    }
                    guard self.isCurrentOperation(operationID), !Task.isCancelled else { return }
                    if let importCompleted {
                        await importCompleted()
                    }
                }
                guard self.isCurrentOperation(operationID), !Task.isCancelled else { return }
                self.errorMessage = ImportUserFacingError.message(for: pipelineError)
                await self.loadHistory()
            } catch {
                guard self.isCurrentOperation(operationID) else { return }
                self.errorMessage = ImportUserFacingError.message(for: error)
                await self.loadHistory()
            }
        }
    }

    private func isCurrentOperation(_ id: UUID) -> Bool {
        activeOperationID == id
            && accountStore?.workspaceRevision == configuredWorkspaceRevision
            && accountStore?.activeAccountID == databaseClient?.accountID
    }

    private func updateProgress(_ update: ImportProgress, operationID: UUID) {
        guard isCurrentOperation(operationID), !Task.isCancelled else { return }
        progress = update
    }
}
