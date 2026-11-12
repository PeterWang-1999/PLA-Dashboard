import Foundation
import Observation

@MainActor
@Observable
final class BIDownloadStore {
    enum SyncPhase {
        case connecting
        case downloading(file: Int, total: Int)
        case importing(ImportProgress)
        case finishing(String)
        case cancelling

        var canCancel: Bool {
            switch self {
            case .connecting, .downloading, .importing: true
            case .finishing, .cancelling: false
            }
        }
    }

    private(set) var workspaces: [String: BIWorkspace] = [:]
    private(set) var connectedAccounts: Set<String> = []
    private(set) var busyAccount: String?
    var errorMessage: String?
    private(set) var syncPhase: SyncPhase?
    var syncResult: String?

    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var command: Task<Void, Never>?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var checkedAccounts: Set<String> = []
    @ObservationIgnored private var activeRuns: Set<UUID> = []
    @ObservationIgnored private var preparingRun: UUID?
    private var storage: URL?

    func workspace(_ accountID: String) -> BIWorkspace {
        workspaces[accountID] ?? BIWorkspace()
    }

    func start() {
        guard loop == nil else { return }
        do {
            let root = try WorkspacePaths.applicationSupportRoot().appendingPathComponent("BI Data", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let file = root.appendingPathComponent("tasks.json")
            if FileManager.default.fileExists(atPath: file.path) {
                workspaces = try JSONDecoder().decode([String: BIWorkspace].self, from: Data(contentsOf: file))
            }
            storage = root
        } catch {
            errorMessage = "无法打开 BI Data 任务记录。\(error.localizedDescription)"
            return
        }

        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.dispatchNext()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func loginSession(_ accountID: String, address: String) throws -> BIWebSession {
        guard let portal = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(portal.scheme?.lowercased() ?? ""),
              portal.host != nil, portal.user == nil, portal.password == nil,
              let account = UUID(uuidString: accountID) else {
            throw BIWebSession.Failure(status: .connectionFailed, message: "请粘贴有效的 BI Data 网页地址。")
        }
        let browser = BIWebSession(portal: portal, accountID: account, allowsLoginLayout: true)
        browser.open()
        return browser
    }

    func saveConnection(_ accountID: String, portal: URL) throws {
        guard change(accountID, {
            if $0.portal != portal { $0.options = BIFilterOptions() }
            $0.portal = portal
        }) else {
            throw BIWebSession.Failure(status: .failed, message: "无法保存 BI Data 连接。")
        }
        connectedAccounts.insert(accountID)
    }

    func checkConnection(_ accountID: String) {
        guard command == nil, !connectedAccounts.contains(accountID),
              !checkedAccounts.contains(accountID),
              let portal = workspaces[accountID]?.portal,
              let account = UUID(uuidString: accountID) else { return }
        checkedAccounts.insert(accountID)
        launch(accountID) { [weak self] in
            let browser = BIWebSession(portal: portal, accountID: account)
            browser.open()
            if (try? await browser.waitForAuthentication()) == true, let self {
                self.connectedAccounts.insert(accountID)
            }
        }
    }

    func refreshFilterOptions(for accountID: String, merchant: String?) async throws {
        let portal = workspaces[accountID]?.portal
        let options = try await loadFilterOptions(for: accountID, merchant: merchant)
        guard workspaces[accountID]?.portal == portal else { return }
        change(accountID) { $0.options = options }
    }

    func loadFilterOptions(for accountID: String, merchant: String?) async throws -> BIFilterOptions {
        guard let portal = workspaces[accountID]?.portal,
              let account = UUID(uuidString: accountID) else {
            throw BIWebSession.Failure(status: .needsLogin, message: "请先在「数据下载」连接 BI Data。")
        }
        let browser = BIWebSession(portal: portal, accountID: account)
        browser.open()
        do {
            let options = try await browser.options(merchant: merchant)
            try Task.checkCancellation()
            return options
        } catch let failure as BIWebSession.Failure {
            try Task.checkCancellation()
            if failure.status == .needsLogin, workspaces[accountID]?.portal == portal {
                connectedAccounts.remove(accountID)
            }
            throw failure
        }
    }

    func saveDefaultCategories(_ categories: [BICategory], accountID: String) -> Bool {
        guard let level = categories.first?.level, categories.allSatisfy({ $0.level == level }) else { return false }
        return change(accountID) { $0.defaultCategories = categories }
    }

    func resetDefaultCategories(accountID: String) -> Bool {
        change(accountID) { $0.defaultCategories = nil }
    }

    func synchronizeProductData(accountStore: AccountStore) {
        guard syncTask == nil, let account = accountStore.activeAccount, account.kind == .selfBuilt,
              let client = accountStore.activeDatabaseClient, client.accountID == account.id else { return }
        let workspace = workspace(account.id)
        guard let portal = workspace.portal, let accountUUID = UUID(uuidString: account.id) else {
            syncResult = "请先在「数据下载」连接 BI Data，再同步产品数据。"
            return
        }
        let operationID: UUID
        do {
            operationID = try accountStore.beginImport(accountID: account.id, workspaceRevision: accountStore.workspaceRevision)
        } catch {
            syncResult = error.localizedDescription
            return
        }
        syncPhase = .connecting
        syncResult = nil
        let filters = BIFilters().usingDefaultCategories(workspace.defaultCategories)
        syncTask = Task {
            defer {
                accountStore.endImport(operationID)
                syncPhase = nil
                syncTask = nil
            }
            await runProductSync(
                filters: filters, portal: portal, accountUUID: accountUUID,
                client: client, accountStore: accountStore, operationID: operationID
            )
        }
    }

    func cancelProductSync() {
        guard syncPhase?.canCancel == true else { return }
        syncPhase = .cancelling
        syncTask?.cancel()
    }

    private func runProductSync(
        filters: BIFilters, portal: URL, accountUUID: UUID,
        client: DatabaseClient, accountStore: AccountStore, operationID: UUID
    ) async {
        let accountID = client.accountID
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(operationID.uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let now = Date()
        let runs = BIDownloadRun.batch(origin: .sync, filters: filters.resolved(through: now), createdAt: now)
        let browser = BIWebSession(portal: portal, accountID: accountUUID)
        var imported = false
        do {
            try Task.checkCancellation()
            browser.open()
            var files: [URL] = []
            for (index, run) in runs.enumerated() {
                try Task.checkCancellation()
                let output = folder.appendingPathComponent("投放产品明细-\(index + 1).xlsx")
                try await browser.export(run, to: output, onSubmissionStarted: {}) { _ in
                    if !Task.isCancelled { syncPhase = .downloading(file: index + 1, total: runs.count) }
                }
                files.append(output)
            }
            try Task.checkCancellation()
            connectedAccounts.insert(accountID)
            guard let first = files.first else { return }
            let result = try await PlaDeliveryDetailImporter(databaseClient: client).importFile(
                sourceURL: first,
                additionalSyncFiles: Array(files.dropFirst()),
                incrementalSync: true
            ) { [weak self] progress in
                await self?.updateSyncProgress(progress)
            }
            imported = true
            try await ImportPipelineRunner.finishImport(
                sourceKind: .plaDeliveryDetail, result: result, databaseClient: client,
                accountKind: .selfBuilt,
                onProgress: { [weak self] progress in await self?.updateSyncProgress(progress) },
                reloadFilterCatalogs: {},
                refreshDashboard: { await accountStore.notifyDataChanged(accountID: accountID) }
            )
            let changed = try await client.countAdsProductDaily(importId: result.importId)
            syncResult = changed == 0 ? "同步完成，投放指标没有变更。" : "同步完成，新增或更新 \(changed) 条投放指标记录。"
        } catch {
            if (error as? BIWebSession.Failure)?.status == .needsLogin {
                connectedAccounts.remove(accountID)
            }
            if imported {
                accountStore.notifyDataChanged(accountID: accountID)
                syncResult = "数据已写入，刷新看板时发生错误。\(error.localizedDescription)"
            } else if Task.isCancelled {
                accountStore.notifyDataChanged(accountID: accountID)
                syncResult = "已取消同步，原有数据已保留。"
            } else {
                syncResult = "同步未完成。\(error.localizedDescription)"
            }
        }
    }

    private func updateSyncProgress(_ progress: ImportProgress) {
        guard !Task.isCancelled else { return }
        switch progress.phase {
        case .finalizing, .rebuildingMetrics, .refreshingDashboard, .completed:
            syncPhase = .finishing(progress.message ?? "正在完成同步…")
        case .failed, .cancelled:
            break
        default:
            syncPhase = .importing(progress)
        }
    }

    @discardableResult
    func savePreset(_ preset: BIPreset, accountID: String) -> Bool {
        change(accountID) { $0.presets.append(preset) }
    }

    @discardableResult
    func saveSchedule(_ schedule: BISchedule, accountID: String) -> Bool {
        var schedule = schedule
        schedule.updateNextRun(after: .now)
        return change(accountID) { workspace in
            if let index = workspace.schedules.firstIndex(where: { $0.id == schedule.id }) {
                workspace.schedules[index] = schedule
            } else {
                workspace.schedules.append(schedule)
            }
        }
    }

    @discardableResult
    func enqueue(_ filters: BIFilters, origin: BIDownloadRun.Origin, accountID: String) -> Bool {
        guard workspaces[accountID]?.portal != nil else { return false }
        let now = Date()
        let runs = BIDownloadRun.batch(origin: origin, filters: filters.resolved(through: now), createdAt: now)
        guard change(accountID, { $0.runs.insert(contentsOf: runs, at: 0) }) else { return false }
        dispatchNext()
        return true
    }

    func retry(_ id: UUID, accountID: String) {
        updateRun(id, accountID: accountID) {
            $0.status = .queued
            $0.detail = nil
        }
        dispatchNext()
    }

    func downloadURL(for run: BIDownloadRun, accountID: String) -> URL? {
        accountDirectory(accountID)?.appendingPathComponent(run.id.uuidString)
            .appendingPathComponent(run.reportKind.rawValue).appendingPathExtension(run.reportKind.fileExtension)
    }

    static func copyToDownloads(_ source: URL, for run: BIDownloadRun) throws -> URL {
        let files = FileManager.default
        let folder = try files.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let weeks = [run.filters.firstWeek, run.filters.lastWeek].compactMap { $0 }.filter {
            $0.range(of: #"^[0-9]{4}-W[0-9]{2}$"#, options: .regularExpression) != nil
        }
        let stem = ([run.reportKind.rawValue] + weeks + [String(run.id.uuidString.prefix(8))]).joined(separator: "_")
        let fileExtension = run.reportKind.fileExtension
        var destination = folder.appendingPathComponent(stem).appendingPathExtension(fileExtension)
        var copy = 2
        while files.fileExists(atPath: destination.path) {
            if files.contentsEqual(atPath: source.path, andPath: destination.path) { return destination }
            destination = folder.appendingPathComponent("\(stem)_\(copy)").appendingPathExtension(fileExtension)
            copy += 1
        }
        try files.copyItem(at: source, to: destination)
        return destination
    }

    private func accountDirectory(_ accountID: String) -> URL? {
        guard UUID(uuidString: accountID) != nil else { return nil }
        return storage?.appendingPathComponent(accountID, isDirectory: true)
    }

    @discardableResult
    private func change(_ id: String, _ edit: (inout BIWorkspace) -> Void) -> Bool {
        guard let storage else { return false }
        var updated = workspaces
        edit(&updated[id, default: BIWorkspace()])
        do {
            try JSONEncoder().encode(updated).write(to: storage.appendingPathComponent("tasks.json"), options: .atomic)
            workspaces = updated
            return true
        } catch {
            errorMessage = "无法保存 BI Data 任务。\(error.localizedDescription)"
            return false
        }
    }

    private func updateRun(_ id: UUID, accountID: String, _ edit: (inout BIDownloadRun) -> Void) {
        change(accountID) {
            guard let index = $0.runs.firstIndex(where: { $0.id == id }) else { return }
            edit(&$0.runs[index])
        }
    }

    private func dispatchNext() {
        guard storage != nil else { return }

        let now = Date()
        for (id, workspace) in workspaces.sorted(by: { $0.key < $1.key }) {
            guard workspace.portal != nil else { continue }
            let due = workspace.schedules.filter { schedule in
                schedule.enabled && schedule.nextRun.map { $0 <= now } == true
            }
            if !due.isEmpty {
                guard change(id, { updated in
                    for schedule in due {
                        guard let index = updated.schedules.firstIndex(where: { $0.id == schedule.id }),
                              let preset = updated.effectivePresets.first(where: { $0.id == schedule.presetID }),
                              let occurrence = BIReportCalendar.occurrence(
                                  hour: schedule.hour, minute: schedule.minute, near: now, next: false
                              ) else { continue }
                        let runs = BIDownloadRun.batch(
                            origin: .scheduled,
                            filters: preset.filters.resolved(through: occurrence),
                            createdAt: now
                        )
                        updated.runs.insert(contentsOf: runs, at: 0)
                        updated.schedules[index].updateNextRun(after: now)
                    }
                }) else { return }
            }
        }

        guard preparingRun == nil else { return }
        let pending = workspaces.flatMap { id, workspace in
            workspace.runs.filter {
                [.queued, .submitting, .generating, .downloading].contains($0.status) && !activeRuns.contains($0.id)
            }.map { (id, $0) }
        }
        if let (id, run) = pending.min(by: { $0.1.submittedAt < $1.1.submittedAt }) {
            export(run, accountID: id)
        }
    }

    private func export(_ run: BIDownloadRun, accountID: String) {
        guard let portal = workspaces[accountID]?.portal,
              let account = UUID(uuidString: accountID),
              let output = downloadURL(for: run, accountID: accountID) else { return }
        preparingRun = run.id
        activeRuns.insert(run.id)
        if run.status == .queued {
            updateRun(run.id, accountID: accountID) { $0.status = .submitting }
        }
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.activeRuns.remove(run.id)
                if self.preparingRun == run.id { self.preparingRun = nil }
            }
            let browser = BIWebSession(portal: portal, accountID: account)
            browser.open()
            do {
                try await browser.export(run, to: output, onSubmissionStarted: {
                    self.preparingRun = nil
                    self.dispatchNext()
                }) { status in
                    self.connectedAccounts.insert(accountID)
                    self.updateRun(run.id, accountID: accountID) { $0.status = status }
                }
                self.updateRun(run.id, accountID: accountID) {
                    $0.status = .completed
                    $0.detail = nil
                }
                do {
                    _ = try Self.copyToDownloads(output, for: run)
                } catch {
                    self.errorMessage = "报表已保存在应用中，但无法复制到「下载」。\(error.localizedDescription)"
                }
            } catch {
                let failure = error as? BIWebSession.Failure
                if failure?.status == .needsLogin { self.connectedAccounts.remove(accountID) }
                self.updateRun(run.id, accountID: accountID) {
                    $0.status = failure?.status ?? .failed
                    $0.detail = failure?.message ?? "无法完成 BI Data 操作，请检查报表页面后重试。"
                }
            }
        }
    }

    private func launch(_ accountID: String, operation: @escaping @MainActor () async -> Void) {
        busyAccount = accountID
        command = Task { [weak self] in
            await operation()
            self?.busyAccount = nil
            self?.command = nil
        }
    }
}
