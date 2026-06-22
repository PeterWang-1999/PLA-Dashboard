import Foundation

struct AdsProductColumnMap: Sendable {
    let dateIndex: Int
    let itemIdIndex: Int
    let campaignIndex: Int
    let currencyCodeIndex: Int
    let costIndex: Int
    let impressionsIndex: Int
    let clicksIndex: Int
    let conversionsIndex: Int
    let conversionValueIndex: Int

    init(headers: [String]) throws {
        func index(of column: String) throws -> Int {
            guard let found = headers.firstIndex(of: column) else {
                throw AdsProductColumnMapError.missingColumn(column)
            }
            return found
        }

        dateIndex = try index(of: "天")
        itemIdIndex = try index(of: "产品 ID")
        campaignIndex = try index(of: "广告系列")
        currencyCodeIndex = try index(of: "货币代码")
        costIndex = try index(of: "费用")
        impressionsIndex = try index(of: "展示次数")
        clicksIndex = try index(of: "点击次数")
        conversionsIndex = try index(of: "转化次数")
        conversionValueIndex = try index(of: "转化价值")
    }

    func value(at index: Int, in fields: [String]) -> String? {
        guard index < fields.count else { return nil }
        let trimmed = fields[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum AdsProductColumnMapError: Error, LocalizedError {
    case missingColumn(String)

    var errorDescription: String? {
        switch self {
        case .missingColumn(let name):
            "文件缺少必需列：\(name)"
        }
    }
}
