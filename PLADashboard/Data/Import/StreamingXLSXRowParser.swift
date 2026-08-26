import Foundation

/// 流式解析 XLSX 工作表行（支持 shared strings、`inlineStr` 与数值单元格；首行为表头）。
struct StreamingXLSXRowParser: Sendable {
    enum Event: Sendable {
        case header([String])
        case row(rowNumber: Int, fields: [String])
    }

    private enum StreamEvent: Sendable {
        case estimate(Int)
        case parsed(Event)
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

    /// 解压工作表后逐行回调。XML 解析作为单一生产任务运行，异步消费端按顺序处理事件。
    /// - Parameter onEstimate: 解压完成后、解析开始前回调数据行预估（不含表头）。
    func forEachEvent(
        onEstimate: (@Sendable (Int) async -> Void)? = nil,
        handler: @escaping @Sendable (Event) async throws -> Void
    ) async throws {
        for try await event in makeEventStream() {
            try Task.checkCancellation()
            switch event {
            case .estimate(let estimate):
                await onEstimate?(estimate)
            case .parsed(let parsedEvent):
                try await handler(parsedEvent)
            }
        }
    }

    private func makeEventStream() -> AsyncThrowingStream<StreamEvent, Error> {
        let fileURL = fileURL
        let worksheetEntryPath = worksheetEntryPath
        let sharedStringsEntryPath = sharedStringsEntryPath

        return AsyncThrowingStream { continuation in
            let producer = Task.detached(priority: .userInitiated) {
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
                    try Task.checkCancellation()

                    let estimate = try XLSXSheetRowCounter.estimateDataRowCount(
                        sheetXMLURL: sheetURL
                    )
                    continuation.yield(.estimate(estimate))

                    let bridge = XLSXSheetXMLBridge(sharedStrings: sharedStrings)
                    bridge.shouldCancel = { Task.isCancelled }
                    var headerEmitted = false
                    var dataRowNumber = 0

                    bridge.onRow = { fields in
                        guard !Task.isCancelled else { return }
                        if !headerEmitted {
                            headerEmitted = true
                            continuation.yield(.parsed(.header(fields)))
                        } else {
                            dataRowNumber += 1
                            continuation.yield(.parsed(.row(rowNumber: dataRowNumber, fields: fields)))
                        }
                    }

                    try bridge.parse(fileURL: sheetURL)
                    try Task.checkCancellation()
                    guard headerEmitted else {
                        throw ParserError.worksheetMissing
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                producer.cancel()
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
    var shouldCancel: (() -> Bool)?

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
        if shouldCancel?() == true {
            parser.abortParsing()
            return
        }
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
