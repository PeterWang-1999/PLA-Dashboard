import Foundation
import XCTest
@testable import PLADashboard

enum BenchmarkTestSupport {
    static func writeTemporaryFile(name: String, contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_" + name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func makeMerchantTSV(rowCount: Int) -> String {
        var lines = [
            "标题\t序号\tcanonical link\t图片链接\t自定义标签 0\t自定义标签 1\t自定义标签 2\t自定义标签 3\t自定义标签 4\tgoogle 商品类别",
        ]
        for index in 0..<rowCount {
            let itemId = String(format: "%08d_00001_US_en", index + 1)
            lines.append(
                "Bench \(index)\t\(itemId)\thttps://example.com/p/\(index)\thttps://example.com/img/\(index).jpg\tEN\t\t\t\t\tApparel & Accessories > Clothing > Shirts & Tops"
            )
        }
        return lines.joined(separator: "\n")
    }

    static func makeAdsCSV(rowCount: Int, days: Int = 20) -> String {
        var lines = [
            "Ador - 产品数据",
            "2026-06-01 - 2026-06-22",
            "天\t产品 ID\t广告系列\t货币代码\t费用\t展示次数\t点击次数\t转化次数\t转化价值",
        ]
        let start = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 6, day: 1))!
        for rowIndex in 0..<rowCount {
            let productIndex = rowIndex % max(1, rowCount / max(1, days))
            let itemId = String(format: "%08d_00001_US_en", productIndex + 1)
            let dayOffset = rowIndex % days
            let day = Calendar(identifier: .gregorian).date(byAdding: .day, value: dayOffset, to: start)!
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            let dayString = formatter.string(from: day)
            let cost = String(format: "%.2f", Double((rowIndex % 50) + 1))
            let convValue = String(format: "$%.2f", Double((rowIndex % 30) + 10))
            lines.append(
                "\(dayString)\t\(itemId)\tCampaign \(rowIndex)\tUSD\t\(cost)\t1000\t50\t2.5\t\(convValue)"
            )
        }
        return lines.joined(separator: "\n")
    }

    static func seedBenchmarkDatabase(
        adsRows: Int,
        merchantRows: Int
    ) async throws -> DatabaseClient {
        let databaseClient = try DatabaseClient.makeInMemoryForTesting()
        let merchantURL = try writeTemporaryFile(name: "bench_merchant.tsv", contents: makeMerchantTSV(rowCount: merchantRows))
        let adsURL = try writeTemporaryFile(name: "bench_ads.csv", contents: makeAdsCSV(rowCount: adsRows))
        defer {
            try? FileManager.default.removeItem(at: merchantURL)
            try? FileManager.default.removeItem(at: adsURL)
        }
        _ = try await MerchantCenterImporter(databaseClient: databaseClient)
            .importFile(sourceURL: merchantURL) { _ in }
        _ = try await AdsProductImporter(databaseClient: databaseClient)
            .importFile(sourceURL: adsURL) { _ in }
        try await databaseClient.rebuildProductWeeklyMetrics()
        return databaseClient
    }
}
