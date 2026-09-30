import XCTest
@testable import PLADashboard

final class DataDashboardCapacityTests: XCTestCase {
    func testDashboardAboveExportLimitIncludesEveryProductAndExportStillRejects() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting()
        let count = DatabaseClient.dashboardExportRowLimit + 1
        try await client.seedDashboardCapacityFixture(count: count)

        let snapshot = try await client.fetchDataDashboard(
            filters: DashboardQueryFilters(), accountKind: .thirdParty
        )
        XCTAssertEqual(snapshot.metrics.first(where: { $0.kind == .spend })?.value, "$50,001.00")
        XCTAssertEqual(snapshot.metrics.first(where: { $0.kind == .sales })?.value, "$100,002.00")
        XCTAssertEqual(snapshot.weeklyTrend.reduce(0) { $0 + $1.costCents }, count * 100)
        XCTAssertEqual(snapshot.dailyTrend.reduce(0) { $0 + $1.costCents }, count * 100)
        XCTAssertEqual(snapshot.campaigns.first?.metrics.costCents, count * 100)
        XCTAssertEqual(snapshot.categories.first?.metrics.costCents, count * 100)
        XCTAssertEqual(snapshot.topProducts.count, 10)
        XCTAssertEqual(snapshot.topProducts.first?.productID, "P000001")

        do {
            _ = try await client.fetchDashboardAllRows(filters: DashboardQueryFilters())
            XCTFail("CSV 必须保留 50,000 行限制")
        } catch DashboardExportError.tooManyRows(let actual, let limit) {
            XCTAssertEqual(actual, count)
            XCTAssertEqual(limit, 50_000)
        }
    }

    func testChartSelectionMatchesExportAcrossFiltersAndEngines() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting()
        try await client.seedDashboardCapacityFixture(count: 12)
        let cases: [DashboardQueryFilters] = [
            DashboardQueryFilters(),
            DashboardQueryFilters(searchText: "P000001"),
            DashboardQueryFilters(customLabelFilter: .value(column: "自定义标签 0", value: "even")),
            DashboardQueryFilters(categoryFilter: .level2("Clothing")),
            DashboardQueryFilters(sort: .roiAscending),
            DashboardQueryFilters(alertFilter: "GMC 缺失"),
            DashboardQueryFilters(alertFilter: "低消费"),
            DashboardQueryFilters(warningLabelEngine: .selfBuiltSnapshot),
            DashboardQueryFilters(alertFilter: "GMC 缺失", warningLabelEngine: .selfBuiltSnapshot),
            DashboardQueryFilters(alertFilter: "高效", warningLabelEngine: .selfBuiltSnapshot),
        ]
        for filters in cases {
            let exported = try await client.fetchDashboardAllRows(filters: filters)
            let selected = try await client.fetchDataDashboardProductSelection(filters: filters)
            XCTAssertEqual(selected.productIDs, exported.rows.map(\.id), "\(filters)")
            XCTAssertEqual(selected.weekStarts, exported.weekStarts)
            let snapshot = try await client.fetchDataDashboard(filters: filters, accountKind: .thirdParty)
            XCTAssertEqual(
                snapshot.weeklyTrend.reduce(0) { $0 + $1.costCents },
                exported.rows.reduce(0) { $0 + $1.sortCostCents }
            )
        }
    }

    func testWeeklyBatchReadDoesNotDuplicateRepeatedProductIDs() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting()
        try await client.seedDashboardCapacityFixture(count: 501)
        let selection = try await client.fetchDataDashboardProductSelection(filters: DashboardQueryFilters())
        let records = try await client.fetchWeeklyMetrics(
            productIds: selection.productIDs + selection.productIDs,
            weekStarts: selection.weekStarts
        )
        XCTAssertEqual(records.count, 501)
        XCTAssertEqual(records.reduce(0) { $0 + $1.costCents }, 50_100)
    }

    func testEmptyDashboardRemainsEmpty() async throws {
        let client = try DatabaseClient.makeInMemoryForTesting()
        let snapshot = try await client.fetchDataDashboard(filters: DashboardQueryFilters(), accountKind: .thirdParty)
        XCTAssertTrue(snapshot.metrics.isEmpty)
        XCTAssertTrue(snapshot.topProducts.isEmpty)
    }
}

private extension DatabaseClient {
    func seedDashboardCapacityFixture(count: Int) throws {
        try createImportJob(ImportJobRecord(
            id: "capacity", sourceKind: "ads_product", fileName: "capacity.csv",
            filePathBookmark: nil, fileChecksum: nil, importedAt: "2026-09-27T00:00:00Z",
            status: "succeeded", totalRows: count, validRows: count,
            invalidRows: 0, warningRows: 0, schemaVersion: 2
        ))
        for start in stride(from: 1, through: count, by: 500) {
            let range = start...min(start + 499, count)
            let products = range.map { index in
                let id = String(format: "P%06d", index)
                return ProductRecord(
                    productId: id, title: "Capacity product", canonicalLink: nil, imageUrl: nil,
                    customLabel0: index.isMultiple(of: 2) ? "even" : "odd",
                    customLabel1: nil, customLabel2: nil, customLabel3: nil, customLabel4: nil,
                    lsin: id, googleProductCategory: "Apparel & Accessories > Clothing > Dresses",
                    firstListedAt: nil, firstSeenAt: nil, lastSeenAt: nil,
                    updatedFromImportId: nil, missingInGmc: index == 1
                )
            }
            try upsertProductsBatch(products, importId: "capacity", importedAt: "2026-09-27T00:00:00Z")
            let ads = products.map { product in
                AdsProductDailyRecord(
                    date: "2026-09-26", itemId: product.productId, productId: product.productId,
                    variantId: nil, campaign: "Campaign", currencyCode: "USD", costMicros: 1_000_000,
                    impressions: 100, clicks: 10, conversions: 1,
                    conversionValueCents: 200, importId: "capacity"
                )
            }
            try insertAdsProductDailyBatch(ads)
        }
        try rebuildAllProductSearchIndex()
        try rebuildProductWeeklyMetrics()
        if count <= 501 {
            let decisions = (1...count).map { index in
                LabelProductDecision(
                    productId: String(format: "P%06d", index), previousLabel: "普通/观察",
                    suggestedLabel: index.isMultiple(of: 2) ? "高效" : "普通/观察",
                    transitionAction: "fixture", reason: "fixture",
                    failHighRetain: false, marginLt1: false, noSignalRecent3: false,
                    noConvGSCurrentWeek: false, roiGe1x: true, marginGe1: true,
                    weeksInLowSampleOld: 0, weeksInPotentialNew: 0
                )
            }
            try persistLabelSnapshot(
                weekId: "2026-09-20", weekStarts: ["2026-09-20"],
                historyNote: "capacity fixture", decisions: decisions
            )
        }
    }
}
