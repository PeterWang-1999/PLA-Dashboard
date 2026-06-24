import Foundation

enum LegacyDatabaseMigrator {
    static let defaultMigratedAccountName = "默认账户"

    static func needsMigration(fileManager: FileManager = .default) throws -> Bool {
        guard try !fileManager.fileExists(atPath: WorkspacePaths.manifestURL().path) else {
            return false
        }
        return try hasLegacyData(fileManager: fileManager)
    }

    static func hasLegacyData(fileManager: FileManager = .default) throws -> Bool {
        let legacyDatabase = try WorkspacePaths.legacyDatabaseURL()
        if fileManager.fileExists(atPath: legacyDatabase.path) {
            return true
        }
        let legacyImports = try WorkspacePaths.legacyImportsRoot()
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: legacyImports.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return true
        }
        return false
    }

    static func migrateIfNeeded(fileManager: FileManager = .default) throws -> WorkspaceAccountsManifest? {
        guard try needsMigration(fileManager: fileManager) else {
            return nil
        }
        return try migrate(fileManager: fileManager)
    }

    static func migrate(fileManager: FileManager = .default) throws -> WorkspaceAccountsManifest {
        let account = WorkspaceAccount.makeDefault(name: defaultMigratedAccountName, kind: .thirdParty)
        let accountDirectory = try WorkspacePaths.accountDirectory(id: account.id)

        try backupLegacyDataIfPresent(fileManager: fileManager)

        let legacyDatabaseURL = try WorkspacePaths.legacyDatabaseURL()
        if fileManager.fileExists(atPath: legacyDatabaseURL.path) {
            let destinationDatabaseURL = try WorkspacePaths.databaseURL(accountID: account.id)
            try moveDatabaseBundle(
                from: legacyDatabaseURL,
                to: destinationDatabaseURL,
                fileManager: fileManager
            )
        }

        let legacyImportsURL = try WorkspacePaths.legacyImportsRoot()
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: legacyImportsURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            let destinationImportsURL = try WorkspacePaths.importsRoot(accountID: account.id)
            if fileManager.fileExists(atPath: destinationImportsURL.path) {
                try fileManager.removeItem(at: destinationImportsURL)
            }
            try fileManager.moveItem(at: legacyImportsURL, to: destinationImportsURL)
        }

        _ = accountDirectory

        let manifest = WorkspaceAccountsManifest(
            schemaVersion: WorkspaceAccountsManifest.currentSchemaVersion,
            activeAccountID: account.id,
            accounts: [account]
        )
        try manifest.validate()
        try WorkspaceAccountPersistence.save(manifest, fileManager: fileManager)
        return manifest
    }

    private static func backupLegacyDataIfPresent(fileManager: FileManager) throws {
        guard try hasLegacyData(fileManager: fileManager) else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupDirectory = try WorkspacePaths.legacyBackupRoot()
            .appendingPathComponent(timestamp, isDirectory: true)
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        let legacyDatabaseURL = try WorkspacePaths.legacyDatabaseURL()
        if fileManager.fileExists(atPath: legacyDatabaseURL.path) {
            try copyDatabaseBundle(
                from: legacyDatabaseURL,
                to: backupDirectory.appendingPathComponent(WorkspacePaths.databaseFileName, isDirectory: false),
                fileManager: fileManager
            )
        }

        let legacyImportsURL = try WorkspacePaths.legacyImportsRoot()
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: legacyImportsURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            try fileManager.copyItem(
                at: legacyImportsURL,
                to: backupDirectory.appendingPathComponent(WorkspacePaths.importsDirectoryName, isDirectory: true)
            )
        }
    }

    private static func moveDatabaseBundle(
        from sourceDatabaseURL: URL,
        to destinationDatabaseURL: URL,
        fileManager: FileManager
    ) throws {
        let destinationDirectory = destinationDatabaseURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: destinationDatabaseURL.path) {
            try fileManager.removeItem(at: destinationDatabaseURL)
        }
        try fileManager.moveItem(at: sourceDatabaseURL, to: destinationDatabaseURL)

        for sidecarURL in WorkspacePaths.databaseSidecarURLs(beside: sourceDatabaseURL) {
            guard fileManager.fileExists(atPath: sidecarURL.path) else { continue }
            let suffix = sidecarURL.path.hasSuffix("-wal") ? "-wal" : "-shm"
            let destinationSidecarURL = URL(fileURLWithPath: destinationDatabaseURL.path + suffix)
            if fileManager.fileExists(atPath: destinationSidecarURL.path) {
                try fileManager.removeItem(at: destinationSidecarURL)
            }
            try fileManager.moveItem(at: sidecarURL, to: destinationSidecarURL)
        }
    }

    private static func copyDatabaseBundle(
        from sourceDatabaseURL: URL,
        to destinationDatabaseURL: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.copyItem(at: sourceDatabaseURL, to: destinationDatabaseURL)
        for sidecarURL in WorkspacePaths.databaseSidecarURLs(beside: sourceDatabaseURL) {
            guard fileManager.fileExists(atPath: sidecarURL.path) else { continue }
            let suffix = sidecarURL.path.hasSuffix("-wal") ? "-wal" : "-shm"
            let destinationSidecarURL = URL(fileURLWithPath: destinationDatabaseURL.path + suffix)
            try fileManager.copyItem(at: sidecarURL, to: destinationSidecarURL)
        }
    }
}
