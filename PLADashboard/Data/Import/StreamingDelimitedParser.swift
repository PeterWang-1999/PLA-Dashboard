import Foundation

struct StreamingDelimitedParser: Sendable {
    enum Event: Sendable {
        case header([String])
        case row(rowNumber: Int, fields: [String])
    }

    let fileURL: URL
    let delimiter: Character

    init(fileURL: URL, delimiter: DelimitedSeparator = .tab) {
        self.fileURL = fileURL
        self.delimiter = delimiter.rawValue
    }

    /// 流式逐行解析，避免一次性读入整个文件。
    func forEachEvent(_ handler: (Event) async throws -> Void) async throws {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var buffer = Data()
        var rowNumber = 0
        var isFirstLine = true

        while true {
            if let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                var lineData = buffer[..<newlineIndex]
                buffer.removeSubrange(...newlineIndex)
                if lineData.last == UInt8(ascii: "\r") {
                    lineData = lineData.dropLast()
                }

                let line = String(decoding: lineData, as: UTF8.self)
                guard !line.isEmpty else { continue }

                let fields = TSVFieldParser.parseFields(line, delimiter: delimiter)
                if isFirstLine {
                    isFirstLine = false
                    try await handler(.header(fields))
                } else {
                    rowNumber += 1
                    try await handler(.row(rowNumber: rowNumber, fields: fields))
                }
                continue
            }

            guard let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty else {
                if !buffer.isEmpty {
                    let line = String(decoding: buffer, as: UTF8.self)
                    buffer.removeAll(keepingCapacity: true)
                    if !line.isEmpty {
                        let fields = TSVFieldParser.parseFields(line, delimiter: delimiter)
                        if isFirstLine {
                            isFirstLine = false
                            try await handler(.header(fields))
                        } else {
                            rowNumber += 1
                            try await handler(.row(rowNumber: rowNumber, fields: fields))
                        }
                    }
                }
                break
            }
            buffer.append(chunk)
        }
    }
}

enum StreamingDelimitedParserError: Error {
    case missingHeader
}
