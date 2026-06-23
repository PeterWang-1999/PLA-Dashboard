import Foundation
import CryptoKit

struct ImportStagingResult: Sendable {
    let importId: String
    let stagedFileURL: URL
    let checksum: String
    let bookmarkData: Data
    let fileName: String
}

enum ImportStagingStore {
    static let importsDirectoryName = "Imports"

    static func applicationSupportDirectory() throws -> URL {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent(DatabaseClient.databaseDirectoryName, isDirectory: true)
            .appendingPathComponent(importsDirectoryName, isDirectory: true)
    }

    /// 将用户选择的文件复制到 App Container staging，并生成 checksum 与 security-scoped bookmark。
    static func stage(
        sourceURL: URL,
        importId: String,
        fileName: String? = nil
    ) throws -> ImportStagingResult {
        let fileManager = FileManager.default
        let resolvedName = fileName ?? sourceURL.lastPathComponent
        let importsRoot = try applicationSupportDirectory()
        let destinationDirectory = importsRoot.appendingPathComponent(importId, isDirectory: true)
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let destinationURL = destinationDirectory.appendingPathComponent(resolvedName)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        _ = try ImportTextEncoding.normalizeToUTF8IfNeeded(at: destinationURL)

        let checksum = try sha256(of: destinationURL)
        let bookmarkData = try destinationURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        return ImportStagingResult(
            importId: importId,
            stagedFileURL: destinationURL,
            checksum: checksum,
            bookmarkData: bookmarkData,
            fileName: resolvedName
        )
    }

    static func resolveBookmark(_ bookmarkData: Data) throws -> URL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return url
    }

    private static func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            guard let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum ImportStagingError: Error, LocalizedError {
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .copyFailed(let message):
            "无法复制文件到 staging：\(message)"
        }
    }
}
