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
        if isImportInProgress {
            throw WorkspaceAccountError.importInProgress
        }
        guard activeAccountID != accountID else { return }

        let client = try DatabaseClient.make(accountID: accountID)
        try await client.migrateIfNeeded()
        let updatedManifest = try WorkspaceAccountPersistence.updateActiveAccountID(accountID)
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
}
