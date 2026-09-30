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
        phase = .loading
        do {
            let loadedManifest = try WorkspaceAccountPersistence.loadOrCreateManifest()
            AccountSettingsMigration.migrateLegacyGlobalSettingsIfNeeded(for: loadedManifest.activeAccountID)
            let client = try DatabaseClient.make(accountID: loadedManifest.activeAccountID)
            try await client.migrateIfNeeded()
            try await Self.purgeLegacyGoogleAdsIfNeeded(
                client: client,
                accountID: loadedManifest.activeAccountID,
                accounts: loadedManifest.accounts
            )
            manifest = loadedManifest
            activeDatabaseClient = client
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
        guard !isSwitchingAccount else { throw WorkspaceAccountError.workspaceChanged }
        guard activeAccountID != accountID else { return }
        isSwitchingAccount = true
        defer { isSwitchingAccount = false }

        let client = try DatabaseClient.make(accountID: accountID)
        try await client.migrateIfNeeded()
        let updatedManifest = try WorkspaceAccountPersistence.updateActiveAccountID(accountID)
        try await Self.purgeLegacyGoogleAdsIfNeeded(
            client: client,
            accountID: accountID,
            accounts: updatedManifest.accounts
        )
        manifest = updatedManifest
        activeDatabaseClient = client
        workspaceRevision &+= 1
    }

    func createAccount(
        name: String,
        kind: WorkspaceAccountKind = .thirdParty
    ) throws -> WorkspaceAccount {
        guard phase == .ready else {
            throw WorkspaceAccountError.invalidManifest("账户尚未就绪")
        }
        let account = try WorkspaceAccountPersistence.createAccount(name: name, kind: kind)
        manifest = try WorkspaceAccountPersistence.load()
        return account
    }

    /// 自建站账户打开时清除遗留 Google Ads 导入（幂等）。
    private static func purgeLegacyGoogleAdsIfNeeded(
        client: DatabaseClient,
        accountID: String,
        accounts: [WorkspaceAccount]
    ) async throws {
        guard accounts.contains(where: { $0.id == accountID && $0.kind == .selfBuilt }) else {
            return
        }
        let didDelete = try await client.purgeLegacyGoogleAdsImports()
        if didDelete {
            try await client.rebuildProductWeeklyMetrics()
        }
    }
}
