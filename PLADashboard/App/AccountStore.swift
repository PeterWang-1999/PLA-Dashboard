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

    func bootstrap() async {
        phase = .loading
        do {
            let loadedManifest = try WorkspaceAccountPersistence.loadOrCreateManifest()
            let client = try DatabaseClient.make(accountID: loadedManifest.activeAccountID)
            try await client.migrateIfNeeded()
            manifest = loadedManifest
            activeDatabaseClient = client
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

        let updatedManifest = try WorkspaceAccountPersistence.updateActiveAccountID(accountID)
        manifest = updatedManifest
        let client = try DatabaseClient.make(accountID: accountID)
        try await client.migrateIfNeeded()
        activeDatabaseClient = client
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
