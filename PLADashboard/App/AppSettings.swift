import SwiftUI

enum AppSettings {
    static let defaultPageSizeKey = "dashboard.defaultPageSize"
    static let sidebarVisibleKey = "dashboard.sidebarVisible"

    static let legacyDataRetentionDaysKey = "data.retentionDays"
    static let legacyLastRetentionPurgeDayKey = "data.lastRetentionPurgeDay"

    static let scopedDataRetentionDaysSuffix = "data.retentionDays"
    static let scopedLastRetentionPurgeDaySuffix = "data.lastRetentionPurgeDay"

    static var defaultPageSize: Int {
        let value = UserDefaults.standard.integer(forKey: defaultPageSizeKey)
        return value > 0 ? value : 30
    }

    static func scopedKey(accountID: String, suffix: String) -> String {
        "accounts.\(accountID).\(suffix)"
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
            scopedDataRetentionDaysSuffix,
            scopedLastRetentionPurgeDaySuffix,
        ]
        return suffixes.contains { suffix in
            userDefaults.object(forKey: scopedKey(accountID: accountID, suffix: suffix)) != nil
        }
    }
}
