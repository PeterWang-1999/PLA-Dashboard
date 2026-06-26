import Foundation

enum ImportTextNormalizationError: Error, LocalizedError {
    case unreadableEncoding
    case fileTooLargeForTranscode(size: UInt64)

    var errorDescription: String? {
        switch self {
        case .unreadableEncoding:
            return "无法识别文件文本编码（支持 UTF-8、UTF-16、GB18030/GBK）"
        case .fileTooLargeForTranscode(let size):
            let megabytes = Double(size) / 1_048_576
            return String(
                format: "文件约 %.0f MB，体积过大无法自动转码。请在导出或 Excel 中另存为 UTF-8 后再导入。",
                megabytes
            )
        }
    }
}

/// 导入文件文本编码检测与 UTF-8 规范化（Foundation `String.Encoding`）。
enum ImportTextEncoding {
    static let gb18030 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
    )

    /// 超过此大小的非 UTF-8 文件不整文件读入内存转码。
    private static let transcodeSizeThreshold: UInt64 = 50 * 1024 * 1024

    enum Detected: Sendable, Equatable {
        case utf8(stripBOM: Bool)
        case utf16LittleEndian
        case utf16BigEndian
        case gb18030
    }

    /// 根据 BOM 与采样字节判断源编码。
    static func detect(preview: Data) -> Detected {
        if preview.starts(with: [0xEF, 0xBB, 0xBF]) {
            return .utf8(stripBOM: true)
        }
        if preview.starts(with: [0xFF, 0xFE]) {
            if preview.count >= 4, preview[2] == 0, preview[3] == 0 {
                return .utf16LittleEndian
            }
            return .utf16LittleEndian
        }
        if preview.starts(with: [0xFE, 0xFF]) {
            return .utf16BigEndian
        }

        let sample = Data(preview.prefix(65_536))
        if String(data: sample, encoding: .utf8) != nil {
            return .utf8(stripBOM: false)
        }
        if String(data: sample, encoding: gb18030) != nil {
            return .gb18030
        }
        return .utf8(stripBOM: false)
    }

    /// 将非 UTF-8 文件原地转为 UTF-8；已是 UTF-8 则保持字节不变（大文件仅采样检测，避免整文件读入内存）。
    @discardableResult
    static func normalizeToUTF8IfNeeded(at fileURL: URL) throws -> Bool {
        let fileSize = try fileSize(at: fileURL)
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let preview = try handle.read(upToCount: 65_536) ?? Data()
        guard !preview.isEmpty else { return false }

        let detected = detect(preview: preview)

        switch detected {
        case .utf8(let stripBOM):
            if stripBOM {
                return try stripUTF8BOM(at: fileURL)
            }
            return false

        case .utf16LittleEndian:
            guard fileSize <= transcodeSizeThreshold else {
                throw ImportTextNormalizationError.fileTooLargeForTranscode(size: fileSize)
            }
            try handle.seek(toOffset: 0)
            let data = try handle.readToEnd() ?? Data()
            return try transcodeAndWrite(data, encoding: .utf16LittleEndian, to: fileURL)

        case .utf16BigEndian:
            guard fileSize <= transcodeSizeThreshold else {
                throw ImportTextNormalizationError.fileTooLargeForTranscode(size: fileSize)
            }
            try handle.seek(toOffset: 0)
            let data = try handle.readToEnd() ?? Data()
            return try transcodeAndWrite(data, encoding: .utf16BigEndian, to: fileURL)

        case .gb18030:
            guard fileSize <= transcodeSizeThreshold else {
                throw ImportTextNormalizationError.fileTooLargeForTranscode(size: fileSize)
            }
            try handle.seek(toOffset: 0)
            let data = try handle.readToEnd() ?? Data()
            if String(data: data, encoding: .utf8) != nil {
                return false
            }
            return try transcodeAndWrite(data, encoding: gb18030, to: fileURL)
        }
    }

    /// 表头列名规范化：去 BOM、首尾空白。
    static func normalizeHeaderField(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fileSize(at fileURL: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        return attributes[.size] as? UInt64 ?? 0
    }

    private static func stripUTF8BOM(at fileURL: URL) throws -> Bool {
        let sourceHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? sourceHandle.close() }

        _ = try sourceHandle.read(upToCount: 3)

        let tempURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(".encoding-normalize-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)

        let destinationHandle = try FileHandle(forWritingTo: tempURL)
        defer { try? destinationHandle.close() }

        while true {
            guard let chunk = try sourceHandle.read(upToCount: 65_536), !chunk.isEmpty else { break }
            try destinationHandle.write(contentsOf: chunk)
        }

        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
        return true
    }

    private static func transcodeAndWrite(
        _ data: Data,
        encoding: String.Encoding,
        to fileURL: URL
    ) throws -> Bool {
        guard let text = String(data: data, encoding: encoding) else {
            throw ImportTextNormalizationError.unreadableEncoding
        }
        try writeUTF8(text, to: fileURL)
        return true
    }

    private static func writeUTF8(_ text: String, to fileURL: URL) throws {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        try Data(normalized.utf8).write(to: fileURL, options: .atomic)
    }
}
