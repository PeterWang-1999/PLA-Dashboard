import Foundation

/// 阶段 5 性能基准与导入批大小配置（集中调优入口）。
enum BenchmarkConfiguration: Sendable {
    /// 导入批量写入行数（经 500→1000 基准验证后采用）。
    static let importBatchSize = 1_000

    /// ETL 批量 INSERT 周指标行数。
    static let etlInsertBatchSize = 5_000

    /// 性能测试默认 Ads 行数（CI / 快速回归）。
    static let performanceTestAdsRowCount = 10_000

    /// 完整基准 Ads 行数（需本地 BenchmarkFixtures）。
    static let fullBenchmarkAdsRowCount = 1_000_000

    /// 配套 Merchant SKU 数（完整基准）。
    static let fullBenchmarkMerchantRowCount = 50_000

    /// 看板首屏查询 SLA 上限（秒，Release 参考机）。
    static let dashboardQuerySLASeconds = 0.8

    /// 看板首屏查询 SLA 下限（秒）。
    static let dashboardQuerySLAMinSeconds = 0.3

    /// 环境变量：设为 `1` 且 fixture 存在时运行百万行性能测试。
    static var runsFullBenchmark: Bool {
        ProcessInfo.processInfo.environment["PLA_RUN_FULL_BENCHMARK"] == "1"
    }

    /// 基准 fixture 目录（仓库根 `BenchmarkFixtures/`，不入 Git）。
    static var fixturesDirectory: URL {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Benchmark
            .deletingLastPathComponent() // Data
            .deletingLastPathComponent() // PLADashboard
            .deletingLastPathComponent() // repo root
        return repoRoot.appendingPathComponent("BenchmarkFixtures", isDirectory: true)
    }

    static var adsFixtureURL: URL {
        fixturesDirectory.appendingPathComponent("Ads_1M.csv")
    }

    static var merchantFixtureURL: URL {
        fixturesDirectory.appendingPathComponent("Merchant_50K.tsv")
    }

    static var adsManifestURL: URL {
        fixturesDirectory.appendingPathComponent("Ads_manifest.json")
    }

    static func performanceAdsRowTarget() -> Int {
        if runsFullBenchmark, FileManager.default.fileExists(atPath: adsFixtureURL.path) {
            return fullBenchmarkAdsRowCount
        }
        return performanceTestAdsRowCount
    }
}
