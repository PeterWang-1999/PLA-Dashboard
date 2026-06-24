import Foundation

enum WorkspaceAccountPersistence {
    static let defaultFirstAccountName = "默认账户"

    static func loadOrCreateManifest(fileManager: FileManager = .default) throws -> WorkspaceAccountsManifest {
        try detectIncompleteMigration(fileManager: fileManager)

        if let manifest = try load(fileManager: fileManager) {
            try manifest.validate()
            return manifest
        }

        if let migratedManifest = try LegacyDatabaseMigrator.migrateIfNeeded(fileManager: fileManager) {
            return migratedManifest
        }

        let account = WorkspaceAccount.makeDefault(name: defaultFirstAccountName, kind: .thirdParty)
        _ = try WorkspacePaths.accountDirectory(id: account.id)
        let manifest = WorkspaceAccountsManifest(
            schemaVersion: WorkspaceAccountsManifest.currentSchemaVersion,
            activeAccountID: account.id,
            accounts: [account]
        )
        try manifest.validate()
        try save(manifest, fileManager: fileManager)
        return manifest
    }

    static func load(fileManager: FileManager = .default) throws -> WorkspaceAccountsManifest? {
        let url = try WorkspacePaths.manifestURL()
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WorkspaceAccountsManifest.self, from: data)
    }

    static func save(_ manifest: WorkspaceAccountsManifest, fileManager: FileManager = .default) throws {
        try manifest.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)

        let manifestURL = try WorkspacePaths.manifestURL()
        let temporaryURL = manifestURL.appendingPathExtension("tmp")
        try data.write(to: temporaryURL, options: .atomic)
        if fileManager.fileExists(atPath: manifestURL.path) {
            _ = try fileManager.replaceItemAt(manifestURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: manifestURL)
        }
    }

    @discardableResult
    static func createAccount(
        name: String,
        kind: WorkspaceAccountKind,
        fileManager: FileManager = .default
    ) throws -> WorkspaceAccount {
        guard var manifest = try load(fileManager: fileManager) else {
            throw WorkspaceAccountError.invalidManifest("尚未初始化账户配置")
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw WorkspaceAccountError.invalidManifest("账户名称不能为空")
        }

        let account = WorkspaceAccount.makeDefault(name: trimmedName, kind: kind)
        _ = try WorkspacePaths.accountDirectory(id: account.id)
        manifest.accounts.append(account)
        try save(manifest, fileManager: fileManager)
        return account
    }

    static func updateActiveAccountID(
        _ id: String,
        fileManager: FileManager = .default
    ) throws -> WorkspaceAccountsManifest {
        guard var manifest = try load(fileManager: fileManager) else {
            throw WorkspaceAccountError.invalidManifest("尚未初始化账户配置")
        }
        guard manifest.accounts.contains(where: { $0.id == id }) else {
            throw WorkspaceAccountError.accountNotFound(id)
        }
        manifest.activeAccountID = id
        try save(manifest, fileManager: fileManager)
        return manifest
    }

    private static func detectIncompleteMigration(fileManager: FileManager) throws {
        let manifestExists = try fileManager.fileExists(atPath: WorkspacePaths.manifestURL().path)
        let accountsRoot = try WorkspacePaths.accountsRoot()
        let accountDirectories = try fileManager.contentsOfDirectory(
            at: accountsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }

        if !manifestExists, !accountDirectories.isEmpty {
            throw WorkspaceAccountError.incompleteMigration("检测到未完成的账户迁移，请重试启动应用")
        }
    }
}
