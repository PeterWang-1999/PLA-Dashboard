import XCTest
@testable import PLADashboard

final class MerchantFinishPerformanceTests: XCTestCase {
    func testMerchantFinishPairedBaseline() async throws {
        let client = try await BenchmarkTestSupport.seedBenchmarkDatabase(adsRows: 10_000, merchantRows: 500)
        let jobs = try await client.fetchImportJobs()
        let job = try XCTUnwrap(jobs.first { $0.sourceKindValue == .merchantCenter })
        let result = ImportResult(importId: job.id, stagedFileURL: FileManager.default.temporaryDirectory, job: job, errors: [])
        let countBefore = try await client.productWeeklyMetricsCount()
        var oldSamples: [Double] = []
        var newSamples: [Double] = []
        for sample in 0..<12 {
            // 交替顺序，首对预热；只计导入收尾数据库工作，不计解析、UI 与真实磁盘。
            for legacy in sample.isMultiple(of: 2) ? [true, false] : [false, true] {
                let start = CFAbsoluteTimeGetCurrent()
                if legacy {
                    if try await client.hasFactTableData() {
                        try await client.rebuildProductWeeklyMetrics()
                        try await client.reconcileOrphanProducts()
                    }
                } else {
                    try await ImportPipelineRunner.finishImport(sourceKind: .merchantCenter, result: result,
                        databaseClient: client, accountKind: .thirdParty,
                        onProgress: { _ in }, reloadFilterCatalogs: {}, refreshDashboard: {})
                }
                let milliseconds = (CFAbsoluteTimeGetCurrent() - start) * 1_000
                if sample > 0 {
                    if legacy { oldSamples.append(milliseconds) } else { newSamples.append(milliseconds) }
                }
            }
        }
        let countAfter = try await client.productWeeklyMetricsCount()
        XCTAssertEqual(countBefore, countAfter)
        func statistics(_ samples: [Double]) -> [String: Double] {
            let sorted = samples.sorted()
            return ["p50_ms": sorted[sorted.count / 2], "p95_ms": sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1]]
        }
        let payload: [String: Any] = ["ads_rows": 10_000, "products": 500, "warm_samples": 11,
            "legacy": statistics(oldSamples), "optimized": statistics(newSamples),
            "legacy_samples_ms": oldSamples, "optimized_samples_ms": newSamples]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "merchant-finish-paired-baseline"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
