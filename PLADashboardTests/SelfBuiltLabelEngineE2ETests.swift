import XCTest
@testable import PLADashboard

/// 真实 PLA + Product Sales 大文件端到端验收（默认跳过）。
///
/// 运行：
/// ```bash
/// PLA_E2E_LABEL_FILES=1 xcodebuild -scheme PLADashboard -destination 'platform=macOS' \
///   test -only-testing:PLADashboardTests/SelfBuiltLabelEngineE2ETests
/// ```
final class SelfBuiltLabelEngineE2ETests: XCTestCase {
    private let plaPath =
        "/Users/litb/Downloads/临时_未分类/PLA投放表现_投放产品明细数据导出.xlsx"
    private let salesPath =
        "/Users/litb/Downloads/临时_未分类/product_sales_detail_20260710_172242_ZRGQ.csv"

    override func setUp() {
        super.setUp()
        executionTimeAllowance = 3_600
    }

    func testRealPLAAndSalesLabelDistribution() async throws {
        let shouldRun = ProcessInfo.processInfo.environment["PLA_E2E_LABEL_FILES"] == "1"
            || FileManager.default.fileExists(atPath: "/tmp/pla_e2e_label_files")
        guard shouldRun else {
            throw XCTSkip("Set PLA_E2E_LABEL_FILES=1 or touch /tmp/pla_e2e_label_files.")
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: plaPath), fm.fileExists(atPath: salesPath) else {
            throw XCTSkip("Real PLA/Sales files not found at expected Downloads paths.")
        }

        let client = try DatabaseClient.makeInMemoryForTesting()
        let plaURL = URL(fileURLWithPath: plaPath)
        let salesURL = URL(fileURLWithPath: salesPath)

        // 1) 先导投放（无毛利时会几乎全普通）
        print("E2E: importing PLA…")
        let plaResult = try await ImportPipelineRunner.importFile(
            sourceKind: .plaDeliveryDetail,
            sourceURL: plaURL,
            fileName: plaURL.lastPathComponent,
            databaseClient: client,
            accountKind: .selfBuilt
        ) { progress in
            if let message = progress.message {
                print("  PLA \(progress.phase): \(message) rows=\(progress.processedRows)")
            }
        }
        XCTAssertEqual(plaResult.job.status, ImportJobStatus.succeeded.rawValue)
        print("E2E: PLA validRows=\(plaResult.job.validRows)")

        try await ImportPipelineRunner.finishImport(
            sourceKind: .plaDeliveryDetail,
            result: plaResult,
            databaseClient: client,
            accountKind: .selfBuilt,
            onProgress: { progress in
                if let message = progress.message { print("  finish PLA: \(message)") }
            },
            reloadFilterCatalogs: {},
            refreshDashboard: {}
        )

        let afterPLA = try await client.loadLatestLabelDecisionsByProductId()
        let afterPLACounts = Self.countLabels(afterPLA)
        print("E2E: labels after PLA-only: \(afterPLACounts)")

        // 2) 再导毛利，同周必须刷新快照
        print("E2E: importing Sales…")
        let salesResult = try await ImportPipelineRunner.importFile(
            sourceKind: .salesReport,
            sourceURL: salesURL,
            fileName: salesURL.lastPathComponent,
            databaseClient: client,
            accountKind: .selfBuilt
        ) { progress in
            if let message = progress.message {
                print("  Sales \(progress.phase): \(message) rows=\(progress.processedRows)")
            }
        }
        XCTAssertEqual(salesResult.job.status, ImportJobStatus.succeeded.rawValue)
        print("E2E: Sales validRows=\(salesResult.job.validRows)")

        try await ImportPipelineRunner.finishImport(
            sourceKind: .salesReport,
            result: salesResult,
            databaseClient: client,
            accountKind: .selfBuilt,
            onProgress: { progress in
                if let message = progress.message { print("  finish Sales: \(message)") }
            },
            reloadFilterCatalogs: {},
            refreshDashboard: {}
        )

        let labels = try await client.loadLatestLabelDecisionsByProductId()
        let counts = Self.countLabels(labels)
        print("E2E: final label counts: \(counts)")
        print("E2E: total products=\(labels.count)")

        let weekStarts = try await Self.reportingWeeks(client: client)
        let coverage = try await client.salesGrossProfitCoverage(weekStarts: weekStarts)
        let metrics = try await client.buildLabelMetrics(weekStarts: weekStarts)
        let withGP = metrics.products.filter { $0.grossProfit6wCents > 0 }.count
        let withGS = metrics.products.filter { $0.grossSales6wCents > 0 }.count
        let withListed = metrics.products.filter { ($0.firstListedAt?.isEmpty == false) }.count
        let withCMS3 = metrics.products.filter {
            $0.primaryCMS3 != LabelEngineConstants.unclassifiedCMS3
        }.count
        let dataNormal = metrics.products.filter(\.dataNormal).count
        let catBench = metrics.products.filter {
            $0.benchmarkSource == LabelEngineConstants.benchmarkSourceCategory
        }.count
        let enterProbe = metrics.products.filter {
            $0.clicks6w >= 300 && ($0.weightedMarginReturn ?? 0) >= 1.0
        }.count

        let report = """
            total=\(labels.count)
            \(LabelEngineConstants.labelObservation)=\(counts[LabelEngineConstants.labelObservation, default: 0])
            \(LabelEngineConstants.labelOld)=\(counts[LabelEngineConstants.labelOld, default: 0])
            \(LabelEngineConstants.labelPotential)=\(counts[LabelEngineConstants.labelPotential, default: 0])
            \(LabelEngineConstants.labelHigh)=\(counts[LabelEngineConstants.labelHigh, default: 0])
            \(LabelEngineConstants.labelLow)=\(counts[LabelEngineConstants.labelLow, default: 0])
            afterPLA=\(afterPLACounts)
            salesValid=\(salesResult.job.validRows) salesInvalid=\(salesResult.job.invalidRows)
            weeks=\(weekStarts.joined(separator: ","))
            withGS=\(withGS) withGP=\(withGP) withListed=\(withListed) withCMS3=\(withCMS3)
            dataNormal=\(dataNormal) catBench=\(catBench) matureMarginGe1=\(enterProbe)
            dbSalesRowsGS=\(coverage.salesRowsWithGS) dbSalesRowsGP=\(coverage.salesRowsWithGP)
            dbSalesProductsGS=\(coverage.salesProductsWithGS) dbSalesProductsGP=\(coverage.salesProductsWithGP)
            dbWeeklyProductsGS=\(coverage.weeklyProductsWithGS) dbWeeklyProductsGP=\(coverage.weeklyProductsWithGP)
            dbSalesGrossSum=\(coverage.salesGrossSumCents) dbSalesProfitSum=\(coverage.salesProfitSumCents)
            siteROI=\(metrics.thresholds.siteBenchmarkROI.map { String(format: "%.4f", $0) } ?? "nil")
            highMarginThr=\(String(format: "%.4f", metrics.thresholds.highMarginThreshold))
            matureP50=\(metrics.thresholds.matureMarginP50.map { String(format: "%.4f", $0) } ?? "nil") matureN=\(metrics.thresholds.matureSampleN)
            newGSp50=\(metrics.thresholds.newGSP50Cents.map { String($0) } ?? "nil") newGSp75=\(metrics.thresholds.newGSP75Cents.map { String($0) } ?? "nil") newN=\(metrics.thresholds.newPositiveN)
            oldGSp50=\(metrics.thresholds.oldGSP50Cents.map { String($0) } ?? "nil") oldN=\(metrics.thresholds.oldPositiveN)
            """
        let reportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pla_e2e_label_counts.txt")
        try report.write(to: reportURL, atomically: true, encoding: .utf8)
        print("E2E: wrote counts to \(reportURL.path)")
        let attachment = XCTAttachment(string: report)
        attachment.name = "label-counts"
        attachment.lifetime = .keepAlways
        add(attachment)

        // 与 Python 冷启动权威口径对齐（同文件、同报告周）：
        // 普通/观察=10974，低样本老品=530，潜力新品=174，高效=65，低效=50
        XCTAssertEqual(labels.count, 11_793)
        XCTAssertEqual(withGS, 3_566, "有 GS 的产品数应与 Python 全网格一致")
        XCTAssertGreaterThanOrEqual(withGP, 3_400, "有毛利的产品数应接近 Python")
        XCTAssertEqual(
            counts[LabelEngineConstants.labelHigh, default: 0],
            65,
            "高效数量应对齐 Python"
        )
        XCTAssertEqual(
            counts[LabelEngineConstants.labelLow, default: 0],
            50,
            "低效数量应对齐 Python"
        )
        XCTAssertEqual(
            counts[LabelEngineConstants.labelPotential, default: 0],
            174,
            "潜力新品数量应对齐 Python"
        )
        XCTAssertEqual(
            counts[LabelEngineConstants.labelOld, default: 0],
            530,
            "低样本老品数量应对齐 Python"
        )
        XCTAssertEqual(
            counts[LabelEngineConstants.labelObservation, default: 0],
            10_974,
            "普通/观察数量应对齐 Python"
        )
    }

    private static func countLabels(_ map: [String: String]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for label in map.values {
            counts[label, default: 0] += 1
        }
        return counts
    }

    private static func reportingWeeks(client: DatabaseClient) async throws -> [String] {
        let latestDay = try await client.fetchLatestMetricDay()
        let endDate = try XCTUnwrap(latestDay.flatMap(WeekCalendar.parseDay(_:)))
        let weeks = WeekCalendar.reportingWeekStarts(endingAt: endDate)
        XCTAssertEqual(weeks.count, LabelEngineConstants.reportingWeekCount)
        return weeks
    }
}
