import Foundation

/// 串行执行工作区磁盘操作；UI 只接收准备完成的 Sendable 状态。
actor WorkspaceAccountService {
    struct PreparedWorkspace: Sendable {
        let manifest: WorkspaceAccountsManifest
        let client: DatabaseClient
    }

    private let openDatabase: @Sendable (String) throws -> DatabaseClient

    init(openDatabase: @escaping @Sendable (String) throws -> DatabaseClient = {
        try DatabaseClient.make(accountID: $0)
    }) {
        self.openDatabase = openDatabase
    }

    func bootstrap() async throws -> PreparedWorkspace {
        let manifest = try WorkspaceAccountPersistence.loadOrCreateManifest()
        AccountSettingsMigration.migrateLegacyGlobalSettingsIfNeeded(for: manifest.activeAccountID)
        let client = try openDatabase(manifest.activeAccountID)
        try await prepareLegacyData(client: client, manifest: manifest)
        return PreparedWorkspace(manifest: manifest, client: client)
    }

    func switchAccount(to accountID: String) async throws -> PreparedWorkspace {
        guard let manifest = try WorkspaceAccountPersistence.load(),
              manifest.accounts.contains(where: { $0.id == accountID }) else {
            throw WorkspaceAccountError.accountNotFound(accountID)
        }
        let client = try openDatabase(accountID)
        try await prepareLegacyData(client: client, manifest: manifest)
        // 初始化成功后才持久化选择，避免失败时磁盘与界面账户不同。
        let updated = try WorkspaceAccountPersistence.updateActiveAccountID(accountID)
        return PreparedWorkspace(manifest: updated, client: client)
    }

    func createAccount(name: String, kind: WorkspaceAccountKind) throws -> (
        account: WorkspaceAccount, manifest: WorkspaceAccountsManifest
    ) {
        let account = try WorkspaceAccountPersistence.createAccount(name: name, kind: kind)
        guard let manifest = try WorkspaceAccountPersistence.load() else {
            throw WorkspaceAccountError.invalidManifest("账户配置丢失")
        }
        return (account, manifest)
    }

    private func prepareLegacyData(client: DatabaseClient, manifest: WorkspaceAccountsManifest) async throws {
        guard manifest.accounts.contains(where: { $0.id == client.accountID && $0.kind == .selfBuilt }) else {
            return
        }
        if try await client.purgeLegacyGoogleAdsImports() {
            try await client.rebuildProductWeeklyMetrics()
        }
    }
}
