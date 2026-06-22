import Foundation
import Observation

@Observable
final class ImportViewModel {
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
            await importMerchantFile(at: url)
        }
    }

    func importSampleFile() {
        guard let url = Bundle.main.url(forResource: "SampleMerchant", withExtension: "tsv") else {
            errorMessage = "未找到内置样例文件 SampleMerchant.tsv"
            return
        }
        importTask?.cancel()
        importTask = Task {
            await importMerchantFile(at: url, fileName: "SampleMerchant.tsv")
        }
    }

    func cancelImport() {
        importTask?.cancel()
    }

    private func importMerchantFile(at url: URL, fileName: String? = nil) async {
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

        let importer = MerchantCenterImporter(databaseClient: databaseClient)

        do {
            let result = try await importer.importFile(sourceURL: url, fileName: fileName) { [weak self] update in
                await MainActor.run {
                    self?.progress = update
                }
            }
            await MainActor.run {
                latestResult = result
                latestErrors = result.errors
                isImporting = false
            }
            onCatalogReload?(result.stagedFileURL)
            await loadHistory()
        } catch let merchantError as MerchantCenterImportError {
            await MainActor.run {
                errorMessage = merchantError.localizedDescription
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
