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
}
