import Foundation

enum AccountSettingsMigration {
    static let legacyMigratedAccountIDKey = "accounts.settings.legacyMigratedAccountID"

    /// 将升级前全局 UserDefaults 设置一次性迁移到指定账户。
    static func migrateLegacyGlobalSettingsIfNeeded(
        for accountID: String,
        userDefaults: UserDefaults = .standard
    ) {
        if userDefaults.string(forKey: legacyMigratedAccountIDKey) != nil {
            return
        }

        guard hasLegacyGlobalSettings(userDefaults: userDefaults) else {
            return
        }

        if userDefaults.object(forKey: AppSettings.legacyHighEfficiencyROIMultiplierKey) is Double {
            setHighEfficiencyROIMultiplier(
                userDefaults.object(forKey: AppSettings.legacyHighEfficiencyROIMultiplierKey) as! Double,
                accountID: accountID,
                userDefaults: userDefaults
            )
        }

        if userDefaults.object(forKey: AppSettings.legacyLowEfficiencyMinClicksKey) is Int {
            setLowEfficiencyMinClicks(
                userDefaults.object(forKey: AppSettings.legacyLowEfficiencyMinClicksKey) as! Int,
                accountID: accountID,
                userDefaults: userDefaults
            )
        }

        if userDefaults.object(forKey: AppSettings.legacyDataRetentionDaysKey) != nil {
            setDataRetentionDays(
                userDefaults.integer(forKey: AppSettings.legacyDataRetentionDaysKey),
                accountID: accountID,
                userDefaults: userDefaults
            )
        }

        if let lastPurgeDay = userDefaults.string(forKey: AppSettings.legacyLastRetentionPurgeDayKey) {
            setLastRetentionPurgeDay(lastPurgeDay, accountID: accountID, userDefaults: userDefaults)
        }

        userDefaults.set(accountID, forKey: legacyMigratedAccountIDKey)
    }

    private static func hasLegacyGlobalSettings(userDefaults: UserDefaults) -> Bool {
        if userDefaults.object(forKey: AppSettings.legacyHighEfficiencyROIMultiplierKey) != nil {
            return true
        }
        if userDefaults.object(forKey: AppSettings.legacyLowEfficiencyMinClicksKey) != nil {
            return true
        }
        if userDefaults.object(forKey: AppSettings.legacyDataRetentionDaysKey) != nil {
            return true
        }
        if userDefaults.string(forKey: AppSettings.legacyLastRetentionPurgeDayKey) != nil {
            return true
        }
        return false
    }

    private static func setHighEfficiencyROIMultiplier(
        _ value: Double,
        accountID: String,
        userDefaults: UserDefaults
    ) {
        AppSettings.setHighEfficiencyROIMultiplier(value, accountID: accountID, userDefaults: userDefaults)
    }

    private static func setLowEfficiencyMinClicks(
        _ value: Int,
        accountID: String,
        userDefaults: UserDefaults
    ) {
        AppSettings.setLowEfficiencyMinClicks(value, accountID: accountID, userDefaults: userDefaults)
    }

    private static func setDataRetentionDays(
        _ value: Int,
        accountID: String,
        userDefaults: UserDefaults
    ) {
        AppSettings.setDataRetentionDays(value, accountID: accountID, userDefaults: userDefaults)
    }

    private static func setLastRetentionPurgeDay(
        _ value: String,
        accountID: String,
        userDefaults: UserDefaults
    ) {
        AppSettings.setLastRetentionPurgeDay(value, accountID: accountID, userDefaults: userDefaults)
    }
}
