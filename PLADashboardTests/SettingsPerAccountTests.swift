import XCTest
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

        AppSettings.setDataRetentionDays(60, accountID: accountA, userDefaults: userDefaults)
        AppSettings.setDataRetentionDays(180, accountID: accountB, userDefaults: userDefaults)

        XCTAssertEqual(AppSettings.dataRetentionDays(accountID: accountA, userDefaults: userDefaults), 60)
        XCTAssertEqual(AppSettings.dataRetentionDays(accountID: accountB, userDefaults: userDefaults), 180)
    }

    func testLegacyMigrationCopiesToDefaultAccount() {
        let defaultAccountID = "legacy-default-\(UUID().uuidString)"
        let otherAccountID = "legacy-other-\(UUID().uuidString)"

        userDefaults.set(90, forKey: AppSettings.legacyDataRetentionDaysKey)
        userDefaults.set("2026-06-20", forKey: AppSettings.legacyLastRetentionPurgeDayKey)

        AccountSettingsMigration.migrateLegacyGlobalSettingsIfNeeded(
            for: defaultAccountID,
            userDefaults: userDefaults
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

        let importA = try await seedAdsDaily(client: clientA)
        let importB = try await seedAdsDaily(client: clientB)

        AppSettings.setDataRetentionDays(30, accountID: accountA)
        AppSettings.setDataRetentionDays(0, accountID: accountB)
        AppSettings.setLastRetentionPurgeDay(nil, accountID: accountA)
        AppSettings.setLastRetentionPurgeDay(nil, accountID: accountB)

        let countBeforeA = try await clientA.countAdsProductDaily(importId: importA)
        let countBeforeB = try await clientB.countAdsProductDaily(importId: importB)
        XCTAssertEqual(countBeforeA, 2)
        XCTAssertEqual(countBeforeB, 2)

        try await clientA.runScheduledRetentionPurgeIfNeeded()
        try await clientB.runScheduledRetentionPurgeIfNeeded()

        let countAfterA = try await clientA.countAdsProductDaily(importId: importA)
        let countAfterB = try await clientB.countAdsProductDaily(importId: importB)
        XCTAssertEqual(countAfterA, 1)
        XCTAssertEqual(countAfterB, 2)
    }

    private func makeInMemoryClient(accountID: String) throws -> DatabaseClient {
        try DatabaseClient.makeInMemoryForTesting(accountID: accountID)
    }

    private func seedAdsDaily(client: DatabaseClient) async throws -> String {
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

        let result = try await AdsProductImporter(databaseClient: client)
            .importFile(sourceURL: adsURL) { _ in }
        return result.importId
    }

    private func writeTemporaryFile(name: String, contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
