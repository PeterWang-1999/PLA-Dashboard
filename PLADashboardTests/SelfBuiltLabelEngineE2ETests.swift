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
        let report = """
            total=\(labels.count)
            \(LabelEngineConstants.labelObservation)=\(counts[LabelEngineConstants.labelObservation, default: 0])
            \(LabelEngineConstants.labelOld)=\(counts[LabelEngineConstants.labelOld, default: 0])
            \(LabelEngineConstants.labelPotential)=\(counts[LabelEngineConstants.labelPotential, default: 0])
            \(LabelEngineConstants.labelHigh)=\(counts[LabelEngineConstants.labelHigh, default: 0])
            \(LabelEngineConstants.labelLow)=\(counts[LabelEngineConstants.labelLow, default: 0])
            afterPLA=\(afterPLACounts)
            """
        let reportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pla_e2e_label_counts.txt")
        try report.write(to: reportURL, atomically: true, encoding: .utf8)
        print("E2E: wrote counts to \(reportURL.path)")
        let attachment = XCTAttachment(string: report)
        attachment.name = "label-counts"
        attachment.lifetime = .keepAlways
        add(attachment)

        // 离线诊断期望量级（报告周约 2026-05-24…2026-06-28）：
        // 普通/观察 ~10974，低样本老品 ~530，潜力新品 ~174，高效 ~65，低效 ~50
        XCTAssertGreaterThan(labels.count, 5_000, "应有大量产品参与标签")
        XCTAssertGreaterThan(
            counts[LabelEngineConstants.labelOld, default: 0],
            100,
            "低样本老品不应接近 0（否则仍像无毛利全普通）"
        )
        XCTAssertGreaterThan(
            counts[LabelEngineConstants.labelPotential, default: 0],
            50,
            "潜力新品不应接近 0"
        )
        XCTAssertGreaterThan(
            counts[LabelEngineConstants.labelHigh, default: 0],
            20,
            "高效不应接近 0"
        )
        XCTAssertGreaterThan(
            counts[LabelEngineConstants.labelLow, default: 0],
            10,
            "低效不应接近 0"
        )

        let observation = counts[LabelEngineConstants.labelObservation, default: 0]
        let observationShare = Double(observation) / Double(max(labels.count, 1))
        XCTAssertLessThan(observationShare, 0.98, "普通/观察占比不应接近 100%")
    }

    private static func countLabels(_ map: [String: String]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for label in map.values {
            counts[label, default: 0] += 1
        }
        return counts
    }
}
