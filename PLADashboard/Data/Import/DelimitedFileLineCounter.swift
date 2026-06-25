import Foundation

enum DelimitedFileLineCounter {
    /// 预估数据行数（不含表头与 `linesToSkip` 前缀行），与 `StreamingDelimitedParser` 计数规则一致。
    static func estimateDataRowCount(fileURL: URL, linesToSkip: Int = 0) throws -> Int {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var buffer = Data()
        var skippedLines = 0
        var nonEmptyLinesAfterSkips = 0

        while true {
            if let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                var lineData = buffer[..<newlineIndex]
                buffer.removeSubrange(...newlineIndex)
                if lineData.last == UInt8(ascii: "\r") {
                    lineData = lineData.dropLast()
                }

                let line = String(decoding: lineData, as: UTF8.self)
                if skippedLines < linesToSkip {
                    skippedLines += 1
                    continue
                }

                if !line.isEmpty {
                    nonEmptyLinesAfterSkips += 1
                }
                continue
            }

            guard let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty else {
                if !buffer.isEmpty {
                    let line = String(decoding: buffer, as: UTF8.self)
                    if skippedLines < linesToSkip {
                        skippedLines += 1
                    } else if !line.isEmpty {
                        nonEmptyLinesAfterSkips += 1
                    }
                }
                break
            }
            buffer.append(chunk)
        }

        guard nonEmptyLinesAfterSkips > 0 else { return 0 }
        return max(0, nonEmptyLinesAfterSkips - 1)
    }
}
