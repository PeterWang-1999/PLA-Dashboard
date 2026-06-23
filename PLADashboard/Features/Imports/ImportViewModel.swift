import Foundation
import Observation

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

    func configure(
        databaseClient: DatabaseClient,
        onCatalogReload: @escaping (URL) -> Void
    ) {
        self.databaseClient = databaseClient
        self.onCatalogReload = onCatalogReload
    }

    func presentImportPicker() {
        showFileImporter = true
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
        importTask?.cancel()
        importTask = Task {
            await importFile(at: url)
        }
    }

    func importSampleFile() {
        guard let url = Bundle.main.url(
            forResource: selectedSourceKind.sampleResourceName,
            withExtension: selectedSourceKind.sampleFileExtension
        ) else {
            errorMessage = "未找到内置样例文件 \(selectedSourceKind.sampleResourceName).\(selectedSourceKind.sampleFileExtension)"
            return
        }
        importTask?.cancel()
        importTask = Task {
            await importFile(
                at: url,
                fileName: "\(selectedSourceKind.sampleResourceName).\(selectedSourceKind.sampleFileExtension)"
            )
        }
    }

    private func importFile(at url: URL, fileName: String? = nil) async {
        guard let databaseClient else {
            errorMessage = "数据库未就绪"
            return
        }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        isImporting = true
        errorMessage = nil
        latestResult = nil
        latestErrors = []
        progress = nil

        do {
            let result: ImportResult
            switch selectedSourceKind {
            case .merchantCenter:
                let importer = MerchantCenterImporter(databaseClient: databaseClient)
                result = try await importer.importFile(sourceURL: url, fileName: fileName) { [weak self] update in
                    await MainActor.run {
                        self?.progress = update
                    }
                }
            case .salesReport:
                let importer = SalesReportImporter(databaseClient: databaseClient)
                result = try await importer.importFile(sourceURL: url, fileName: fileName) { [weak self] update in
                    await MainActor.run {
                        self?.progress = update
                    }
                }
            case .adsProduct:
                let importer = AdsProductImporter(databaseClient: databaseClient)
                result = try await importer.importFile(sourceURL: url, fileName: fileName) { [weak self] update in
                    await MainActor.run {
                        self?.progress = update
                    }
                }
            }

            await MainActor.run {
                latestResult = result
                latestErrors = result.errors
                isImporting = false
            }

            if selectedSourceKind == .merchantCenter {
                onCatalogReload?(result.stagedFileURL)
            }

            await loadHistory()
        } catch let pipelineError as ImportPipelineError {
            await MainActor.run {
                errorMessage = pipelineError.localizedDescription
                isImporting = false
            }
            await loadHistory()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isImporting = false
            }
            await loadHistory()
        }
    }
}
