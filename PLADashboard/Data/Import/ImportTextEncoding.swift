import Foundation

enum ImportTextNormalizationError: Error, LocalizedError {
    case unreadableEncoding

    var errorDescription: String? {
        switch self {
        case .unreadableEncoding:
            "无法识别文件文本编码（支持 UTF-8、UTF-16、GB18030/GBK）"
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

    /// 将非 UTF-8（或无 BOM 的 GBK）文件原地转为 UTF-8；已是 UTF-8 则尽量保持字节不变。
    @discardableResult
    static func normalizeToUTF8IfNeeded(at fileURL: URL) throws -> Bool {
        let data = try Data(contentsOf: fileURL)
        let detected = detect(preview: data)

        switch detected {
        case .utf8(let stripBOM):
            if stripBOM {
                let stripped = Data(data.dropFirst(3))
                guard let text = String(data: stripped, encoding: .utf8) else {
                    throw ImportTextNormalizationError.unreadableEncoding
                }
                try writeUTF8(text, to: fileURL)
                return true
            }
            if String(data: data, encoding: .utf8) != nil {
                return false
            }
            return try transcodeAndWrite(data, encoding: gb18030, to: fileURL)

        case .utf16LittleEndian:
            return try transcodeAndWrite(data, encoding: .utf16LittleEndian, to: fileURL)

        case .utf16BigEndian:
            return try transcodeAndWrite(data, encoding: .utf16BigEndian, to: fileURL)

        case .gb18030:
            return try transcodeAndWrite(data, encoding: gb18030, to: fileURL)
        }
    }

    /// 表头列名规范化：去 BOM、首尾空白。
    static func normalizeHeaderField(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
