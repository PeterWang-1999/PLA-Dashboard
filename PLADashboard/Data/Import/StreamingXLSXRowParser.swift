import Foundation

/// 流式解析 XLSX 工作表行（支持 shared strings、`inlineStr` 与数值单元格；首行为表头）。
struct StreamingXLSXRowParser: Sendable {
    enum Event: Sendable {
        case header([String])
        case row(rowNumber: Int, fields: [String])
    }

    enum ParserError: Error, LocalizedError {
        case worksheetMissing
        case parseFailed(String)

        var errorDescription: String? {
            switch self {
            case .worksheetMissing:
                "XLSX 中未找到工作表数据"
            case .parseFailed(let message):
                "XLSX 解析失败：\(message)"
            }
        }
    }

    let fileURL: URL
    private let worksheetEntryPath = "xl/worksheets/sheet1.xml"
    private let sharedStringsEntryPath = "xl/sharedStrings.xml"

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// 解压工作表后逐行回调；解析线程在每行处理完成前阻塞，形成背压。
    func forEachEvent(_ handler: @escaping @Sendable (Event) async throws -> Void) async throws {
        let fileURL = self.fileURL
        let worksheetEntryPath = self.worksheetEntryPath
        let sharedStringsEntryPath = self.sharedStringsEntryPath

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let tempDirectory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("pla-xlsx-\(UUID().uuidString)", isDirectory: true)

                do {
                    try FileManager.default.createDirectory(
                        at: tempDirectory,
                        withIntermediateDirectories: true
                    )
                    defer { try? FileManager.default.removeItem(at: tempDirectory) }

                    let sharedStrings = try Self.loadSharedStrings(
                        from: fileURL,
                        entryPath: sharedStringsEntryPath,
                        tempDirectory: tempDirectory
                    )

                    let sheetURL = tempDirectory.appendingPathComponent("sheet1.xml")
                    try ZipEntryExtractor.extractEntry(
                        named: worksheetEntryPath,
                        from: fileURL,
                        to: sheetURL
                    )

                    let bridge = XLSXSheetXMLBridge(sharedStrings: sharedStrings)
                    var headerEmitted = false
                    var dataRowNumber = 0
                    var handlerError: Error?

                    bridge.onRow = { fields in
                        if handlerError != nil { return }

                        let event: Event
                        if !headerEmitted {
                            headerEmitted = true
                            event = .header(fields)
                        } else {
                            dataRowNumber += 1
                            event = .row(rowNumber: dataRowNumber, fields: fields)
                        }

                        let gate = DispatchSemaphore(value: 0)
                        Task {
                            do {
                                try await handler(event)
                            } catch {
                                handlerError = error
                            }
                            gate.signal()
                        }
                        gate.wait()
                    }

                    try bridge.parse(fileURL: sheetURL)

                    if let handlerError {
                        continuation.resume(throwing: handlerError)
                    } else if !headerEmitted {
                        continuation.resume(throwing: ParserError.worksheetMissing)
                    } else {
                        continuation.resume()
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func loadSharedStrings(
        from zipURL: URL,
        entryPath: String,
        tempDirectory: URL
    ) throws -> [String] {
        let stringsURL = tempDirectory.appendingPathComponent("sharedStrings.xml")
        do {
            try ZipEntryExtractor.extractEntry(
                named: entryPath,
                from: zipURL,
                to: stringsURL
            )
        } catch ZipEntryExtractor.ExtractorError.entryNotFound {
            return []
        }

        let loader = XLSXSharedStringsLoader()
        return try loader.load(fileURL: stringsURL)
    }
}

// MARK: - Shared strings

final class XLSXSharedStringsLoader: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var currentText = ""
    private var isCapturingText = false
    private var parseError: Error?

    func load(fileURL: URL) throws -> [String] {
        guard let stream = InputStream(url: fileURL) else {
            throw StreamingXLSXRowParser.ParserError.parseFailed("无法打开 sharedStrings")
        }
        let parser = XMLParser(stream: stream)
        parser.delegate = self
        guard parser.parse() else {
            if let parseError {
                throw parseError
            }
            throw StreamingXLSXRowParser.ParserError.parseFailed(
                parser.parserError?.localizedDescription ?? "sharedStrings 解析失败"
            )
        }
        if let parseError {
            throw parseError
        }
        return strings
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "si":
            currentText = ""
        case "t":
            isCapturingText = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isCapturingText else { return }
        currentText.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "t":
            isCapturingText = false
        case "si":
            strings.append(currentText)
            currentText = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = StreamingXLSXRowParser.ParserError.parseFailed(parseError.localizedDescription)
    }
}

// MARK: - Sheet XML bridge

final class XLSXSheetXMLBridge: NSObject, XMLParserDelegate {
    var onRow: (([String]) -> Void)?

    private let sharedStrings: [String]
    private var currentCellRef: String?
    private var currentCellType: String?
    private var currentRowCells: [Int: String] = [:]
    private var textBuffer = ""
    private var isCapturingText = false
    private var maxColumnIndex = -1
    private var parseError: Error?

    init(sharedStrings: [String] = []) {
        self.sharedStrings = sharedStrings
    }

    func parse(fileURL: URL) throws {
        guard let stream = InputStream(url: fileURL) else {
            throw StreamingXLSXRowParser.ParserError.parseFailed("无法打开工作表 XML")
        }
        let parser = XMLParser(stream: stream)
        parser.delegate = self
        guard parser.parse() else {
            if let parseError {
                throw parseError
            }
            throw StreamingXLSXRowParser.ParserError.parseFailed(
                parser.parserError?.localizedDescription ?? "未知错误"
            )
        }
        if let parseError {
            throw parseError
        }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "row":
            currentRowCells = [:]
        case "c":
            currentCellRef = attributeDict["r"]
            currentCellType = attributeDict["t"]
            textBuffer = ""
        case "v", "t":
            isCapturingText = true
            textBuffer = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isCapturingText else { return }
        textBuffer.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "v":
            isCapturingText = false
            commitCurrentCellValue()
        case "t":
            isCapturingText = false
            if currentCellType == "inlineStr" {
                commitCurrentCellValue()
            }
        case "c":
            currentCellRef = nil
            currentCellType = nil
            textBuffer = ""
        case "row":
            let width = max(maxColumnIndex + 1, (currentRowCells.keys.max() ?? -1) + 1)
            var fields = Array(repeating: "", count: max(width, 0))
            for (index, value) in currentRowCells where index < fields.count {
                fields[index] = value
            }
            onRow?(fields)
            if let maxInRow = currentRowCells.keys.max() {
                maxColumnIndex = max(maxColumnIndex, maxInRow)
            }
            currentRowCells = [:]
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = StreamingXLSXRowParser.ParserError.parseFailed(parseError.localizedDescription)
    }

    private func commitCurrentCellValue() {
        guard let ref = currentCellRef,
              let columnIndex = Self.columnIndex(fromCellReference: ref) else { return }
        let raw = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String
        if currentCellType == "s",
           let index = Int(raw),
           index >= 0,
           index < sharedStrings.count {
            value = sharedStrings[index]
        } else {
            value = raw
        }
        currentRowCells[columnIndex] = value
        maxColumnIndex = max(maxColumnIndex, columnIndex)
        textBuffer = ""
    }

    /// `A1` / `AA12` → 0-based column index.
    static func columnIndex(fromCellReference ref: String) -> Int? {
        var column = 0
        var sawLetter = false
        for scalar in ref.unicodeScalars {
            if CharacterSet.letters.contains(scalar) {
                sawLetter = true
                let value = Int(scalar.value)
                let mapped: Int
                if (65...90).contains(value) {
                    mapped = value - 64
                } else if (97...122).contains(value) {
                    mapped = value - 96
                } else {
                    return nil
                }
                column = column * 26 + mapped
            } else if sawLetter {
                break
            }
        }
        guard sawLetter else { return nil }
        return column - 1
    }
}
