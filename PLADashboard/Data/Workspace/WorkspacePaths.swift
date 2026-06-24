import Foundation

enum WorkspacePaths {
    static let applicationDirectoryName = "PLA Dashboard"
    static let manifestFileName = "accounts.json"
    static let accountsDirectoryName = "accounts"
    static let importsDirectoryName = "Imports"
    static let databaseFileName = "pla_dashboard.sqlite"
    static let legacyBackupDirectoryName = "legacy"

    /// 单元测试注入根目录，避免写入真实 Application Support。
    static var testRootOverride: URL?

    static func applicationSupportRoot() throws -> URL {
        if let testRootOverride {
            return testRootOverride
        }
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = appSupport.appendingPathComponent(applicationDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func manifestURL() throws -> URL {
        try applicationSupportRoot().appendingPathComponent(manifestFileName, isDirectory: false)
    }

    static func accountsRoot() throws -> URL {
        let url = try applicationSupportRoot().appendingPathComponent(accountsDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func accountDirectory(id: String) throws -> URL {
        let url = try accountsRoot().appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func databaseURL(accountID: String) throws -> URL {
        try accountDirectory(id: accountID).appendingPathComponent(databaseFileName, isDirectory: false)
    }

    static func importsRoot(accountID: String) throws -> URL {
        let url = try accountDirectory(id: accountID).appendingPathComponent(importsDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func legacyDatabaseURL() throws -> URL {
        try applicationSupportRoot().appendingPathComponent(databaseFileName, isDirectory: false)
    }

    static func legacyImportsRoot() throws -> URL {
        try applicationSupportRoot().appendingPathComponent(importsDirectoryName, isDirectory: true)
    }

    static func legacyBackupRoot() throws -> URL {
        let url = try applicationSupportRoot().appendingPathComponent(legacyBackupDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func databaseSidecarURLs(beside databaseURL: URL) -> [URL] {
        [
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm"),
        ]
    }
}
