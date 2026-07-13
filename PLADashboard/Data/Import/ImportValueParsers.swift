import Foundation

enum ImportValueParsers {
    private static let isoDatePattern = try! NSRegularExpression(
        pattern: #"^(\d{4})-(\d{2})-(\d{2})$"#
    )

    private static let slashDatePattern = try! NSRegularExpression(
        pattern: #"^(\d{4})[/-](\d{1,2})[/-](\d{1,2})$"#
    )

    static func parseISODate(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        if isoDatePattern.firstMatch(in: trimmed, range: range) != nil {
            return trimmed
        }

        if let match = slashDatePattern.firstMatch(in: trimmed, range: range),
           match.numberOfRanges >= 4,
           let yearRange = Range(match.range(at: 1), in: trimmed),
           let monthRange = Range(match.range(at: 2), in: trimmed),
           let dayRange = Range(match.range(at: 3), in: trimmed) {
            let year = String(trimmed[yearRange])
            let month = String(format: "%02d", Int(trimmed[monthRange]) ?? 0)
            let day = String(format: "%02d", Int(trimmed[dayRange]) ?? 0)
            return "\(year)-\(month)-\(day)"
        }

        let formats = ["yyyy-MM-dd", "yyyy/M/d", "M/d/yyyy", "MM/dd/yyyy"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter.string(from: date)
            }
        }

        return nil
    }

    static func parseCurrencyToCents(_ raw: String) -> Int? {
        guard let decimal = parseDecimalString(raw) else { return nil }
        return intValueByScaling(decimal, fractionalDigits: 2)
    }

    static func parseCostToMicros(_ raw: String) -> Int? {
        guard let decimal = parseDecimalString(raw) else { return nil }
        return intValueByScaling(decimal, fractionalDigits: 6)
    }

    /// 先按目标小数位舍入再乘 10^n 取整。
    /// 毛利 CSV 常含 30+ 位小数；直接 `NSDecimalMultiplyByPowerOf10` 后取 `intValue`
    /// 会因有效位过长误返回 0，导致 `gross_profit_cents` 大面积丢失。
    private static func intValueByScaling(_ decimal: Decimal, fractionalDigits: Int16) -> Int {
        var value = decimal
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, Int(fractionalDigits), .plain)
        var scaled = rounded
        var result = Decimal()
        NSDecimalMultiplyByPowerOf10(&result, &scaled, fractionalDigits, .plain)
        var intPart = Decimal()
        NSDecimalRound(&intPart, &result, 0, .plain)
        return (intPart as NSDecimalNumber).intValue
    }

    static func parseInteger(_ raw: String) -> Int? {
        let cleaned = stripNumericDecorations(raw)
        guard !cleaned.isEmpty, let value = Int(cleaned) else { return nil }
        return value
    }

    /// 解析展示/点击等计数；兼容 Excel 导出的 `25401.0`。
    static func parseCount(_ raw: String) -> Int? {
        if let value = parseInteger(raw) {
            return value
        }
        guard let decimal = parseDecimal(raw) else { return nil }
        guard decimal.isFinite, decimal >= 0 else { return nil }
        return Int(decimal.rounded())
    }

    static func parseDecimal(_ raw: String) -> Double? {
        guard let decimal = parseDecimalString(raw) else { return nil }
        return (decimal as NSDecimalNumber).doubleValue
    }

    private static func parseDecimalString(_ raw: String) -> Decimal? {
        let cleaned = stripNumericDecorations(raw)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// 去除 Google Ads / Excel 导出常见的引号、千分位与空白。
    private static func stripNumericDecorations(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("\""), cleaned.hasSuffix("\""), cleaned.count >= 2 {
            cleaned = String(cleaned.dropFirst().dropLast())
        }
        return cleaned
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
