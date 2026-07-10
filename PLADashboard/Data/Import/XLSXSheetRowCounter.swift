import Foundation

/// 从已解压的 worksheet XML 预估数据行数（不含表头），供导入进度条使用。
enum XLSXSheetRowCounter {
    /// 优先读取 `<dimension ref="A1:AA168472"/>`；若无则扫描 `<row` 标签数。
    static func estimateDataRowCount(sheetXMLURL: URL) throws -> Int {
        if let fromDimension = try peekDimensionDataRowCount(sheetXMLURL: sheetXMLURL) {
            return fromDimension
        }
        return try countRowElementsAsDataRows(sheetXMLURL: sheetXMLURL)
    }

    private static func peekDimensionDataRowCount(sheetXMLURL: URL) throws -> Int? {
        let handle = try FileHandle(forReadingFrom: sheetXMLURL)
        defer { try? handle.close() }

        // dimension 通常出现在文件头部数 KB 内。
        let preview = try handle.read(upToCount: 16_384) ?? Data()
        guard !preview.isEmpty else { return nil }

        let text = String(decoding: preview, as: UTF8.self)
        guard let dimensionKey = text.range(of: "dimension"),
              let refKey = text[dimensionKey.lowerBound...].range(of: "ref=\"") else {
            return nil
        }
        let afterRef = text[refKey.upperBound...]
        guard let endQuote = afterRef.firstIndex(of: "\"") else { return nil }
        let ref = String(afterRef[..<endQuote])
        // e.g. A1:AA168472 or A1
        let parts = ref.split(separator: ":")
        guard let last = parts.last,
              let endRow = rowNumber(fromCellReference: String(last)) else {
            return nil
        }
        // 含表头时 endRow >= 1；数据行 = endRow - 1
        return max(0, endRow - 1)
    }

    private static func countRowElementsAsDataRows(sheetXMLURL: URL) throws -> Int {
        let handle = try FileHandle(forReadingFrom: sheetXMLURL)
        defer { try? handle.close() }

        var buffer = Data()
        var rowTags = 0
        let pattern = Data("<row".utf8)

        while true {
            if let match = buffer.range(of: pattern) {
                rowTags += 1
                buffer.removeSubrange(..<match.upperBound)
                continue
            }

            // 保留可能跨 chunk 的前缀
            let keep = min(buffer.count, pattern.count - 1)
            if buffer.count > keep {
                buffer.removeSubrange(..<(buffer.count - keep))
            }

            guard let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty else {
                break
            }
            buffer.append(chunk)
        }

        return max(0, rowTags - 1)
    }

    private static func rowNumber(fromCellReference ref: String) -> Int? {
        var digits = ""
        for scalar in ref.unicodeScalars {
            if CharacterSet.decimalDigits.contains(scalar) {
                digits.append(Character(scalar))
            } else if !digits.isEmpty {
                break
            }
        }
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }
}
