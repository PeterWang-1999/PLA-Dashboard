import XCTest
@testable import PLADashboard

final class LabelMetricsBuilderTests: XCTestCase {
    private let weekStarts = [
        "2026-05-24",
        "2026-05-31",
        "2026-06-07",
        "2026-06-14",
        "2026-06-21",
        "2026-06-28",
    ]

    func testSafeDivAndPercentile() {
        XCTAssertNil(LabelMetricsBuilder.safeDiv(1, 0))
        XCTAssertEqual(LabelMetricsBuilder.safeDiv(10, 4), 2.5)

        XCTAssertNil(LabelMetricsBuilder.percentile([], 0.5))
        XCTAssertEqual(LabelMetricsBuilder.percentile([10], 0.5), 10)
        // [10,20,30,40] p=0.5 → index 1.5 → 25；p=0.75 → index 2.25 → 32.5
        XCTAssertEqual(LabelMetricsBuilder.percentile([10, 20, 30, 40], 0.5), 25)
        XCTAssertEqual(LabelMetricsBuilder.percentile([10, 20, 30, 40], 0.75), 32.5)
    }

    func testNewProductCutoffIsThreeMonthsBeforeWeekEnd() throws {
        // week start 2026-06-28 → week end 2026-07-04 → -3m = 2026-04-04
        let cutoff = try LabelMetricsBuilder.newProductCutoffDay(currentWeekStart: "2026-06-28")
        XCTAssertEqual(cutoff, "2026-04-04")
    }

    func testWeightedROIUsesSumCVOverSumCost() throws {
        // 仅 1 个产品，6 周花费与转化价值不同，验证 Σ(CV×w)/Σ(Cost×w)
        var facts: [LabelWeeklyFact] = []
        let costs = [100, 100, 100, 100, 100, 200] // cents
        let cvs = [100, 100, 100, 100, 100, 400]
        for (index, week) in weekStarts.enumerated() {
            facts.append(LabelWeeklyFact(
                productId: "P1",
                weekStart: week,
                costCents: costs[index],
                impressions: 0,
                clicks: 50,
                conversions: 1,
                conversionValueCents: cvs[index],
                grossSalesCents: 100,
                grossProfitCents: 40
            ))
        }

        let result = try LabelMetricsBuilder.build(
            weekStarts: weekStarts,
            weeklyFacts: facts,
            products: [
                LabelProductMeta(productId: "P1", firstListedAt: "2025-01-01", cms3: "Dresses"),
            ]
        )

        let row = try XCTUnwrap(result.products.first)
        let weights = LabelEngineConstants.weekWeights
        var wCost = 0.0
        var wCV = 0.0
        for i in 0..<6 {
            wCost += Double(costs[i]) * weights[i]
            wCV += Double(cvs[i]) * weights[i]
        }
        XCTAssertEqual(row.weightedAdROI!, wCV / wCost, accuracy: 1e-12)
        // 不应等于各周 ROI 的加权平均（最后一周 ROI=2，其余=1）
        let naive = zip(
            costs.map { Double($0) },
            cvs.map { Double($0) }
        ).enumerated().reduce(0.0) { partial, item in
            let (i, pair) = item
            return partial + (pair.1 / pair.0) * weights[i]
        }
        XCTAssertNotEqual(row.weightedAdROI!, naive, accuracy: 1e-9)
    }

    func testCategoryFallsBackToSiteWhenSampleInsufficient() throws {
        let facts = flatFacts(
            productId: "P1",
            costCents: 1_000,
            clicks: 10,
            conversions: 1,
            cvCents: 1_200,
            gsCents: 500,
            gpCents: 200
        )
        let result = try LabelMetricsBuilder.build(
            weekStarts: weekStarts,
            weeklyFacts: facts,
            products: [
                LabelProductMeta(productId: "P1", firstListedAt: "2025-01-01", cms3: "TinyCat"),
            ]
        )
        let row = try XCTUnwrap(result.products.first)
        XCTAssertFalse(row.categorySampleSufficient)
        XCTAssertEqual(row.benchmarkSource, LabelEngineConstants.benchmarkSourceSite)
        XCTAssertEqual(row.appliedBenchmarkROI, result.thresholds.siteBenchmarkROI)
        XCTAssertTrue(row.categoryInsufficientReason.contains("类目花费"))
    }

    func testNewProductAndMarginThresholds() throws {
        // 成熟品：点击≥300、非新品、毛利回报可分位
        var facts: [LabelWeeklyFact] = []
        facts += flatFacts(
            productId: "MATURE",
            costCents: 10_000,
            clicks: 60,
            conversions: 2,
            cvCents: 12_000,
            gsCents: 20_000,
            gpCents: 8_000
        )
        facts += flatFacts(
            productId: "NEW",
            costCents: 5_000,
            clicks: 20,
            conversions: 1,
            cvCents: 8_000,
            gsCents: 15_000,
            gpCents: 6_000
        )

        let result = try LabelMetricsBuilder.build(
            weekStarts: weekStarts,
            weeklyFacts: facts,
            products: [
                LabelProductMeta(productId: "MATURE", firstListedAt: "2025-01-01", cms3: "Cat"),
                LabelProductMeta(productId: "NEW", firstListedAt: "2026-05-01", cms3: "Cat"),
            ]
        )

        let mature = try XCTUnwrap(result.products.first { $0.productId == "MATURE" })
        let newbie = try XCTUnwrap(result.products.first { $0.productId == "NEW" })
        XCTAssertFalse(mature.isNewByFirstListed3m)
        XCTAssertTrue(newbie.isNewByFirstListed3m)
        XCTAssertEqual(mature.clicks6w, 360)
        XCTAssertEqual(result.thresholds.matureSampleN, 1)
        XCTAssertEqual(result.thresholds.highMarginThreshold, max(1.0, mature.weightedMarginReturn!))
        XCTAssertEqual(result.thresholds.newPositiveN, 1)
        XCTAssertEqual(result.thresholds.newGSP50Cents, newbie.weightedGrossSalesCents)
        XCTAssertEqual(result.thresholds.newGSP75Cents, newbie.weightedGrossSalesCents)
    }

    func testDataNormalRejectsZeroMarginRate() throws {
        let facts = flatFacts(
            productId: "P1",
            costCents: 1_000,
            clicks: 10,
            conversions: 1,
            cvCents: 1_000,
            gsCents: 5_000,
            gpCents: 0
        )
        let result = try LabelMetricsBuilder.build(
            weekStarts: weekStarts,
            weeklyFacts: facts,
            products: [
                LabelProductMeta(productId: "P1", firstListedAt: "2025-01-01", cms3: "Cat"),
            ]
        )
        XCTAssertFalse(result.products[0].dataNormal)
        XCTAssertEqual(result.products[0].realizedMarginRate, 0)
    }

    func testActiveWeeksUseConversionsOrGrossSales() throws {
        var facts: [LabelWeeklyFact] = []
        for (index, week) in weekStarts.enumerated() {
            // 近 3 周：仅中间一周有 GS，无转化
            let isSignalWeek = index == 4
            facts.append(LabelWeeklyFact(
                productId: "P1",
                weekStart: week,
                costCents: 100,
                impressions: 0,
                clicks: 1,
                conversions: 0,
                conversionValueCents: 0,
                grossSalesCents: isSignalWeek ? 100 : 0,
                grossProfitCents: isSignalWeek ? 40 : 0
            ))
        }
        let result = try LabelMetricsBuilder.build(
            weekStarts: weekStarts,
            weeklyFacts: facts,
            products: [
                LabelProductMeta(productId: "P1", firstListedAt: "2025-01-01", cms3: "Cat"),
            ]
        )
        let row = try XCTUnwrap(result.products.first)
        XCTAssertEqual(row.activeWeeksRecent3, 1)
        XCTAssertFalse(row.activeCurrentWeek)
        XCTAssertTrue(row.noConvGSCurrentWeek)
    }

    func testBuildFromDatabaseClient() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting()

        let merchantURL = try writeTemporaryFile(
            name: "merchant.tsv",
            contents: """
            标题\t序号\tcanonical link\t图片链接\t自定义标签 0\t自定义标签 1\t自定义标签 2\t自定义标签 3\t自定义标签 4\tgoogle 商品类别
            Dress\tS1001\thttps://example.com/a\thttps://example.com/a.jpg\tEN\t\t\t\t\tApparel & Accessories > Clothing > Dresses
            """
        )
        // 6 个完整周各一天广告，落在 weekStarts 内
        var adsLines = [
            "Ador - 产品数据",
            "2026-05-24 - 2026-07-04",
            "天\t产品 ID\t广告系列\t货币代码\t费用\t展示次数\t点击次数\t转化次数\t转化价值",
        ]
        for week in weekStarts {
            adsLines.append("\(week)\tS1001\tCampaign A\tUSD\t10.00\t100\t50\t2.0\t$15.00")
        }
        let adsURL = try writeTemporaryFile(name: "ads.csv", contents: adsLines.joined(separator: "\n") + "\n")

        var salesLines = ["日期,LSIN,Gross Sales($),毛利额($)"]
        for week in weekStarts {
            salesLines.append("\(week),S1001,$20.00,$8.00")
        }
        let salesURL = try writeTemporaryFile(name: "sales.csv", contents: salesLines.joined(separator: "\n") + "\n")

        defer {
            try? FileManager.default.removeItem(at: merchantURL)
            try? FileManager.default.removeItem(at: adsURL)
            try? FileManager.default.removeItem(at: salesURL)
        }

        _ = try await MerchantCenterImporter(databaseClient: client)
            .importFile(sourceURL: merchantURL) { _ in }
        _ = try await AdsProductImporter(databaseClient: client)
            .importFile(sourceURL: adsURL) { _ in }
        _ = try await SalesReportImporter(databaseClient: client)
            .importFile(sourceURL: salesURL) { _ in }
        try await client.rebuildProductWeeklyMetrics()

        // 写入首次上架（Merchant 路径不带该字段）
        try await client.upsertProductFirstListedAtBatch(
            [(productId: "1001", firstListedAt: "2025-01-01")],
            importId: "listed",
            importedAt: ISO8601DateFormatter().string(from: Date())
        )

        let result = try await client.buildLabelMetrics(weekStarts: weekStarts)
        XCTAssertEqual(result.products.count, 1)
        XCTAssertEqual(result.products[0].primaryCMS3, "Dresses")
        XCTAssertEqual(result.products[0].clicks6w, 300)
        XCTAssertEqual(result.products[0].grossSales6wCents, 12_000)
        XCTAssertEqual(result.products[0].grossProfit6wCents, 4_800)
        XCTAssertNotNil(result.thresholds.siteBenchmarkROI)
    }

    // MARK: - Fixtures

    private func writeTemporaryFile(name: String, contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_" + name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func flatFacts(
        productId: String,
        costCents: Int,
        clicks: Int,
        conversions: Double,
        cvCents: Int,
        gsCents: Int,
        gpCents: Int
    ) -> [LabelWeeklyFact] {
        weekStarts.map { week in
            LabelWeeklyFact(
                productId: productId,
                weekStart: week,
                costCents: costCents,
                impressions: 0,
                clicks: clicks,
                conversions: conversions,
                conversionValueCents: cvCents,
                grossSalesCents: gsCents,
                grossProfitCents: gpCents
            )
        }
    }
}
