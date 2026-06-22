import Foundation

enum TSVFieldParser {
    static func parseFields(_ line: String, delimiter: Character = "\t") -> [String] {
        if delimiter == "\t" {
            return line.components(separatedBy: "\t")
        }
        return line.split(separator: delimiter, omittingEmptySubsequences: false).map(String.init)
    }
}
