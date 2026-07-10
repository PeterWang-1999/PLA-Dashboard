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
    static let importsDirectoryName = WorkspacePaths.importsDirectoryName

    static func importsRoot(accountID: String) throws -> URL {
        try WorkspacePaths.importsRoot(accountID: accountID)
    }

    /// 将用户选择的文件复制到 App Container staging，并生成 checksum 与 bookmark。
    static func stage(
        sourceURL: URL,
        accountID: String,
        importId: String,
        fileName: String? = nil
    ) throws -> ImportStagingResult {
        let fileManager = FileManager.default
        let resolvedName = fileName ?? sourceURL.lastPathComponent
        let importsRoot = try importsRoot(accountID: accountID)
        let destinationDirectory = importsRoot.appendingPathComponent(importId, isDirectory: true)
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let destinationURL = destinationDirectory.appendingPathComponent(resolvedName)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw ImportStagingError.copyFailed(path: sourceURL.path, underlying: error)
        }

        if !ImportSpreadsheetFormat.isBinarySpreadsheet(at: destinationURL) {
            do {
                _ = try ImportTextEncoding.normalizeToUTF8IfNeeded(at: destinationURL)
            } catch {
                try? fileManager.removeItem(at: destinationURL)
                throw ImportStagingError.encodingFailed(path: destinationURL.path, underlying: error)
            }
        }

        let checksum: String
        do {
            checksum = try sha256(of: destinationURL)
        } catch {
            throw ImportStagingError.checksumFailed(path: destinationURL.path, underlying: error)
        }

        let bookmarkData: Data
        do {
            bookmarkData = try makeBookmark(for: destinationURL)
        } catch {
            throw ImportStagingError.bookmarkFailed(path: destinationURL.path, underlying: error)
        }

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
        do {
            return try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withoutImplicitStartAccessing],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            return try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        }
    }

    /// App 容器内文件使用 minimal bookmark；无需 security scope（Apple File System Programming Guide）。
    private static func makeBookmark(for fileURL: URL) throws -> Data {
        try fileURL.bookmarkData(
            options: [.minimalBookmark],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
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
    case copyFailed(path: String, underlying: Error)
    case encodingFailed(path: String, underlying: Error)
    case checksumFailed(path: String, underlying: Error)
    case bookmarkFailed(path: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .copyFailed(_, let underlying):
            return ImportUserFacingError.message(for: underlying, phase: .stagingCopy)
        case .encodingFailed(_, let underlying):
            if let normalization = underlying as? ImportTextNormalizationError {
                return normalization.errorDescription
            }
            return ImportUserFacingError.message(for: underlying, phase: .stagingEncoding)
        case .checksumFailed(_, let underlying):
            return ImportUserFacingError.message(for: underlying, phase: .stagingChecksum)
        case .bookmarkFailed(_, let underlying):
            return ImportUserFacingError.message(for: underlying, phase: .stagingBookmark)
        }
    }
}
