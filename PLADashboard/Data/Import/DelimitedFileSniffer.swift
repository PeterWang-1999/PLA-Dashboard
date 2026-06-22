import Foundation

enum DelimitedSeparator: Character, Sendable {
    case tab = "\t"
    case comma = ","
}

enum DelimitedFileSniffer {
    /// 采样首行判断分隔符；Merchant Center 默认 TSV。
    static func sniffSeparator(firstLine: String) -> DelimitedSeparator {
        let tabCount = firstLine.filter { $0 == "\t" }.count
        let commaCount = firstLine.filter { $0 == "," }.count
        return tabCount >= commaCount ? .tab : .comma
    }

    /// 跳过前 N 行后，用表头行检测分隔符。
    static func detectSeparator(fileURL: URL, linesToSkip: Int = 0) throws -> DelimitedSeparator {
        guard let headerLine = try peekNonEmptyLine(fileURL: fileURL, skipLines: linesToSkip) else {
            return .tab
        }
        return sniffSeparator(firstLine: headerLine)
    }

    static func peekNonEmptyLine(fileURL: URL, skipLines: Int = 0) throws -> String? {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var buffer = Data()
        var skipped = 0

        while true {
            if let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                var lineData = buffer[..<newlineIndex]
                buffer.removeSubrange(...newlineIndex)
                if lineData.last == UInt8(ascii: "\r") {
                    lineData = lineData.dropLast()
                }

                let line = String(decoding: lineData, as: UTF8.self)
                if line.isEmpty { continue }

                if skipped < skipLines {
                    skipped += 1
                    continue
                }
                return line
            }

            guard let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty else {
                if !buffer.isEmpty {
                    let line = String(decoding: buffer, as: UTF8.self)
                    if !line.isEmpty {
                        if skipped < skipLines {
                            return nil
                        }
                        return line
                    }
                }
                return nil
            }
            buffer.append(chunk)
        }
    }
}
