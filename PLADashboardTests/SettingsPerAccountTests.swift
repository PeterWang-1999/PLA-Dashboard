import XCTest
import GRDB
@testable import PLADashboard

final class SettingsPerAccountTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUpWithError() throws {
        defaultsSuiteName = "pla-settings-test-\(UUID().uuidString)"
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
    }

    override func tearDownWithError() throws {
        userDefaults.removePersistentDomain(forName: defaultsSuiteName)
        userDefaults = nil
        defaultsSuiteName = nil
    }

    func testScopedKeysAreIndependent() {
        let accountA = "account-a-\(UUID().uuidString)"
        let accountB = "account-b-\(UUID().uuidString)"

        AppSettings.setHighEfficiencyROIMultiplier(2.2, accountID: accountA, userDefaults: userDefaults)
        AppSettings.setHighEfficiencyROIMultiplier(1.3, accountID: accountB, userDefaults: userDefaults)
        AppSettings.setLowEfficiencyMinClicks(400, accountID: accountA, userDefaults: userDefaults)
        AppSettings.setLowEfficiencyMinClicks(200, accountID: accountB, userDefaults: userDefaults)
        AppSettings.setDataRetentionDays(60, accountID: accountA, userDefaults: userDefaults)
        AppSettings.setDataRetentionDays(180, accountID: accountB, userDefaults: userDefaults)

        XCTAssertEqual(AppSettings.highEfficiencyROIMultiplier(accountID: accountA, userDefaults: userDefaults), 2.2)
        XCTAssertEqual(AppSettings.highEfficiencyROIMultiplier(accountID: accountB, userDefaults: userDefaults), 1.3)
        XCTAssertEqual(AppSettings.lowEfficiencyMinClicks(accountID: accountA, userDefaults: userDefaults), 400)
        XCTAssertEqual(AppSettings.lowEfficiencyMinClicks(accountID: accountB, userDefaults: userDefaults), 200)
        XCTAssertEqual(AppSettings.dataRetentionDays(accountID: accountA, userDefaults: userDefaults), 60)
        XCTAssertEqual(AppSettings.dataRetentionDays(accountID: accountB, userDefaults: userDefaults), 180)
    }

    func testLegacyMigrationCopiesToDefaultAccount() {
        let defaultAccountID = "legacy-default-\(UUID().uuidString)"
        let otherAccountID = "legacy-other-\(UUID().uuidString)"

        userDefaults.set(2.0, forKey: AppSettings.legacyHighEfficiencyROIMultiplierKey)
        userDefaults.set(250, forKey: AppSettings.legacyLowEfficiencyMinClicksKey)
        userDefaults.set(90, forKey: AppSettings.legacyDataRetentionDaysKey)
        userDefaults.set("2026-06-20", forKey: AppSettings.legacyLastRetentionPurgeDayKey)

        AccountSettingsMigration.migrateLegacyGlobalSettingsIfNeeded(
            for: defaultAccountID,
            userDefaults: userDefaults
        )

        XCTAssertEqual(
            AppSettings.highEfficiencyROIMultiplier(accountID: defaultAccountID, userDefaults: userDefaults),
            2.0
        )
        XCTAssertEqual(
            AppSettings.lowEfficiencyMinClicks(accountID: defaultAccountID, userDefaults: userDefaults),
            250
        )
        XCTAssertEqual(
            AppSettings.dataRetentionDays(accountID: defaultAccountID, userDefaults: userDefaults),
            90
        )
        XCTAssertEqual(
            AppSettings.lastRetentionPurgeDay(accountID: defaultAccountID, userDefaults: userDefaults),
            "2026-06-20"
        )
        XCTAssertEqual(
            userDefaults.string(forKey: AccountSettingsMigration.legacyMigratedAccountIDKey),
            defaultAccountID
        )

        AccountSettingsMigration.migrateLegacyGlobalSettingsIfNeeded(
            for: otherAccountID,
            userDefaults: userDefaults
        )
        XCTAssertFalse(AppSettings.hasScopedSettings(accountID: otherAccountID, userDefaults: userDefaults))
        XCTAssertEqual(
            AppSettings.highEfficiencyROIMultiplier(accountID: otherAccountID, userDefaults: userDefaults),
            AnalyticsConfiguration.highEfficiencyROIMultiplier
        )
    }

    func testRetentionPurgeUsesScopedSettings() async throws {
        let accountA = "retention-a-\(UUID().uuidString)"
        let accountB = "retention-b-\(UUID().uuidString)"
        defer {
            AppSettings.setDataRetentionDays(0, accountID: accountA)
            AppSettings.setDataRetentionDays(0, accountID: accountB)
            AppSettings.setLastRetentionPurgeDay(nil, accountID: accountA)
            AppSettings.setLastRetentionPurgeDay(nil, accountID: accountB)
        }

        let clientA = try makeInMemoryClient(accountID: accountA)
        let clientB = try makeInMemoryClient(accountID: accountB)

        try await seedAdsDaily(client: clientA)
        try await seedAdsDaily(client: clientB)

        AppSettings.setDataRetentionDays(30, accountID: accountA)
        AppSettings.setDataRetentionDays(0, accountID: accountB)
        AppSettings.setLastRetentionPurgeDay(nil, accountID: accountA)
        AppSettings.setLastRetentionPurgeDay(nil, accountID: accountB)

        let countBeforeA = try await clientA.adsDailyRowCount()
        let countBeforeB = try await clientB.adsDailyRowCount()
        XCTAssertEqual(countBeforeA, 2)
        XCTAssertEqual(countBeforeB, 2)

        try await clientA.runScheduledRetentionPurgeIfNeeded()
        try await clientB.runScheduledRetentionPurgeIfNeeded()

        let countAfterA = try await clientA.adsDailyRowCount()
        let countAfterB = try await clientB.adsDailyRowCount()
        XCTAssertEqual(countAfterA, 1)
        XCTAssertEqual(countAfterB, 2)
    }

    func testAnalyticsSnapshotUsesAccountID() {
        let accountID = "snapshot-\(UUID().uuidString)"
        defer {
            AppSettings.setHighEfficiencyROIMultiplier(
                AnalyticsConfiguration.highEfficiencyROIMultiplier,
                accountID: accountID
            )
            AppSettings.setLowEfficiencyMinClicks(
                AnalyticsConfiguration.lowEfficiencyMinClicks,
                accountID: accountID
            )
        }

        AppSettings.setHighEfficiencyROIMultiplier(1.9, accountID: accountID)
        AppSettings.setLowEfficiencyMinClicks(350, accountID: accountID)

        let snapshot = AnalyticsSettingsSnapshot.current(accountID: accountID)

        XCTAssertEqual(snapshot.highEfficiencyROIMultiplier, 1.9)
        XCTAssertEqual(snapshot.lowEfficiencyMinClicks, 350)
    }

    private func makeInMemoryClient(accountID: String) throws -> DatabaseClient {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON;")
        }
        let queue = try DatabaseQueue(configuration: config)
        try AppDatabaseMigrator.migrate(queue)
        return DatabaseClient(accountID: accountID, dbQueue: queue)
    }

    private func seedAdsDaily(client: DatabaseClient) async throws {
        let adsURL = try writeTemporaryFile(
            name: "scoped_retention_\(UUID().uuidString).csv",
            contents: """
            Ador - 产品数据
            2026-06-01 - 2026-06-22
            天\t产品 ID\t广告系列\t货币代码\t费用\t展示次数\t点击次数\t转化次数\t转化价值
            2026-05-01\t00000001_00001_US_en\tCampaign A\tUSD\t1.00\t10\t1\t0\t0
            2026-06-20\t00000001_00001_US_en\tCampaign A\tUSD\t2.00\t10\t1\t0\t0
            """
        )
        defer { try? FileManager.default.removeItem(at: adsURL) }

        _ = try await AdsProductImporter(databaseClient: client)
            .importFile(sourceURL: adsURL) { _ in }
    }

    private func writeTemporaryFile(name: String, contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

private extension DatabaseClient {
    func adsDailyRowCount() async throws -> Int {
        try await dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ads_product_daily;") ?? 0
        }
    }
}
