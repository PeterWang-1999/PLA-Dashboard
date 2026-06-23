import Foundation

struct SalesColumnMap: Sendable {
    let dateIndex: Int
    let lsinIndex: Int
    let grossSalesIndex: Int

    init(headers: [String]) throws {
        let normalizedHeaders = headers.map(ImportTextEncoding.normalizeHeaderField)

        func index(of column: String) throws -> Int {
            guard let found = normalizedHeaders.firstIndex(of: column) else {
                throw SalesColumnMapError.missingColumn(column)
            }
            return found
        }

        dateIndex = try index(of: "日期")
        lsinIndex = try index(of: "LSIN")
        grossSalesIndex = try index(of: "Gross Sales($)")
    }

    func value(at index: Int, in fields: [String]) -> String? {
        guard index < fields.count else { return nil }
        let trimmed = fields[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum SalesColumnMapError: Error, LocalizedError {
    case missingColumn(String)

    var errorDescription: String? {
        switch self {
        case .missingColumn(let name):
            "CSV 缺少必需列：\(name)"
        }
    }
}
