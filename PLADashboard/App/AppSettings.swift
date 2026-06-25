import SwiftUI

enum AppSettings {
    static let defaultPageSizeKey = "dashboard.defaultPageSize"
    static let sidebarVisibleKey = "dashboard.sidebarVisible"

    static let legacyHighEfficiencyROIMultiplierKey = "analytics.highEfficiencyROIMultiplier"
    static let legacyLowEfficiencyMinClicksKey = "analytics.lowEfficiencyMinClicks"
    static let legacyDataRetentionDaysKey = "data.retentionDays"
    static let legacyLastRetentionPurgeDayKey = "data.lastRetentionPurgeDay"

    static let scopedHighEfficiencyROIMultiplierSuffix = "analytics.highEfficiencyROIMultiplier"
    static let scopedLowEfficiencyMinClicksSuffix = "analytics.lowEfficiencyMinClicks"
    static let scopedDataRetentionDaysSuffix = "data.retentionDays"
    static let scopedLastRetentionPurgeDaySuffix = "data.lastRetentionPurgeDay"

    @AppStorage(defaultPageSizeKey) static var defaultPageSize = 30
    @AppStorage(sidebarVisibleKey) static var sidebarVisible = true

    static func scopedKey(accountID: String, suffix: String) -> String {
        "accounts.\(accountID).\(suffix)"
    }

    static func highEfficiencyROIMultiplier(accountID: String, userDefaults: UserDefaults = .standard) -> Double {
        let key = scopedKey(accountID: accountID, suffix: scopedHighEfficiencyROIMultiplierSuffix)
        if let stored = userDefaults.object(forKey: key) as? Double {
            return stored
        }
        return AnalyticsConfiguration.highEfficiencyROIMultiplier
    }

    static func setHighEfficiencyROIMultiplier(
        _ value: Double,
        accountID: String,
        userDefaults: UserDefaults = .standard
    ) {
        let key = scopedKey(accountID: accountID, suffix: scopedHighEfficiencyROIMultiplierSuffix)
        userDefaults.set(value, forKey: key)
    }

    static func lowEfficiencyMinClicks(accountID: String, userDefaults: UserDefaults = .standard) -> Int {
        let key = scopedKey(accountID: accountID, suffix: scopedLowEfficiencyMinClicksSuffix)
        if let stored = userDefaults.object(forKey: key) as? Int {
            return stored
        }
        return AnalyticsConfiguration.lowEfficiencyMinClicks
    }

    static func setLowEfficiencyMinClicks(
        _ value: Int,
        accountID: String,
        userDefaults: UserDefaults = .standard
    ) {
        let key = scopedKey(accountID: accountID, suffix: scopedLowEfficiencyMinClicksSuffix)
        userDefaults.set(value, forKey: key)
    }

    static func dataRetentionDays(accountID: String, userDefaults: UserDefaults = .standard) -> Int {
        let key = scopedKey(accountID: accountID, suffix: scopedDataRetentionDaysSuffix)
        if userDefaults.object(forKey: key) != nil {
            return userDefaults.integer(forKey: key)
        }
        return 0
    }

    static func setDataRetentionDays(
        _ value: Int,
        accountID: String,
        userDefaults: UserDefaults = .standard
    ) {
        let key = scopedKey(accountID: accountID, suffix: scopedDataRetentionDaysSuffix)
        userDefaults.set(value, forKey: key)
    }

    static func lastRetentionPurgeDay(accountID: String, userDefaults: UserDefaults = .standard) -> String? {
        let key = scopedKey(accountID: accountID, suffix: scopedLastRetentionPurgeDaySuffix)
        return userDefaults.string(forKey: key)
    }

    static func setLastRetentionPurgeDay(
        _ value: String?,
        accountID: String,
        userDefaults: UserDefaults = .standard
    ) {
        let key = scopedKey(accountID: accountID, suffix: scopedLastRetentionPurgeDaySuffix)
        if let value {
            userDefaults.set(value, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }

    static func hasScopedSettings(accountID: String, userDefaults: UserDefaults = .standard) -> Bool {
        let suffixes = [
            scopedHighEfficiencyROIMultiplierSuffix,
            scopedLowEfficiencyMinClicksSuffix,
            scopedDataRetentionDaysSuffix,
            scopedLastRetentionPurgeDaySuffix,
        ]
        return suffixes.contains { suffix in
            userDefaults.object(forKey: scopedKey(accountID: accountID, suffix: suffix)) != nil
        }
    }
}
