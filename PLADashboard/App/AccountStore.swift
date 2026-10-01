import Foundation
import Observation

@MainActor
@Observable
final class AccountStore {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var manifest: WorkspaceAccountsManifest?
    private(set) var activeDatabaseClient: DatabaseClient?
    /// 账户工作区就绪令牌；仅在 manifest 与 database client 同步后递增，供 SwiftUI `.task(id:)` 触发加载。
    private(set) var workspaceRevision: UInt = 0
    private(set) var isSwitchingAccount = false
    private var activeImportID: UUID?
    private var isBootstrapping = false
    private var isCreatingAccount = false
    private let workspaceService: WorkspaceAccountService

    init(workspaceService: WorkspaceAccountService = WorkspaceAccountService()) {
        self.workspaceService = workspaceService
    }

    var isImportInProgress: Bool { activeImportID != nil }

    /// 在启动异步任务前占用工作区，所有窗口共享此保护。
    func beginImport(accountID: String, workspaceRevision: UInt) throws -> UUID {
        guard phase == .ready, !isSwitchingAccount,
              activeAccountID == accountID,
              self.workspaceRevision == workspaceRevision else {
            throw WorkspaceAccountError.workspaceChanged
        }
        guard activeImportID == nil else { throw WorkspaceAccountError.importInProgress }
        let id = UUID()
        activeImportID = id
        return id
    }

    func endImport(_ id: UUID) {
        guard activeImportID == id else { return }
        activeImportID = nil
    }

    var accounts: [WorkspaceAccount] {
        manifest?.accounts ?? []
    }

    var activeAccountID: String? {
        manifest?.activeAccountID
    }

    var activeAccount: WorkspaceAccount? {
        guard let manifest else { return nil }
        return manifest.accounts.first { $0.id == manifest.activeAccountID }
    }

    var activeCapabilities: WorkspaceCapabilities? {
        activeAccount.map { WorkspaceCapabilities.forKind($0.kind) }
    }

    func bootstrap() async {
        // 多窗口同时出现加载页时，只初始化一次共享工作区。
        guard !isBootstrapping, phase != .ready else { return }
        isBootstrapping = true
        defer { isBootstrapping = false }
        phase = .loading
        do {
            let prepared = try await workspaceService.bootstrap()
            manifest = prepared.manifest
            activeDatabaseClient = prepared.client
            workspaceRevision &+= 1
            phase = .ready
        } catch {
            manifest = nil
            activeDatabaseClient = nil
            phase = .failed(error.localizedDescription)
        }
    }

    func switchAccount(to accountID: String, isImportInProgress: Bool = false) async throws {
        guard phase == .ready else {
            throw WorkspaceAccountError.invalidManifest("账户尚未就绪")
        }
        if isImportInProgress || self.isImportInProgress {
            throw WorkspaceAccountError.importInProgress
        }
        guard !isSwitchingAccount, !isCreatingAccount else { throw WorkspaceAccountError.workspaceChanged }
        guard activeAccountID != accountID else { return }
        isSwitchingAccount = true
        defer { isSwitchingAccount = false }

        let prepared = try await workspaceService.switchAccount(to: accountID)
        manifest = prepared.manifest
        activeDatabaseClient = prepared.client
        workspaceRevision &+= 1
    }

    func createAccount(
        name: String,
        kind: WorkspaceAccountKind = .thirdParty
    ) async throws -> WorkspaceAccount {
        guard phase == .ready else {
            throw WorkspaceAccountError.invalidManifest("账户尚未就绪")
        }
        guard !isSwitchingAccount, !isCreatingAccount else { throw WorkspaceAccountError.workspaceChanged }
        isCreatingAccount = true
        defer { isCreatingAccount = false }
        let created = try await workspaceService.createAccount(name: name, kind: kind)
        manifest = created.manifest
        return created.account
    }
}
