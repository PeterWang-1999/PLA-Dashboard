import SwiftUI

enum AppSettings {
    static let defaultPageSizeKey = "dashboard.defaultPageSize"
    static let sidebarVisibleKey = "dashboard.sidebarVisible"
    static let highEfficiencyROIMultiplierKey = "analytics.highEfficiencyROIMultiplier"
    static let lowEfficiencyMinClicksKey = "analytics.lowEfficiencyMinClicks"
    static let dataRetentionDaysKey = "data.retentionDays"
    static let lastRetentionPurgeDayKey = "data.lastRetentionPurgeDay"

    @AppStorage(defaultPageSizeKey) static var defaultPageSize = 30
    @AppStorage(sidebarVisibleKey) static var sidebarVisible = true

    static var highEfficiencyROIMultiplier: Double {
        get {
            let stored = UserDefaults.standard.object(forKey: highEfficiencyROIMultiplierKey) as? Double
            return stored ?? AnalyticsConfiguration.highEfficiencyROIMultiplier
        }
        set {
            UserDefaults.standard.set(newValue, forKey: highEfficiencyROIMultiplierKey)
        }
    }

    static var lowEfficiencyMinClicks: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: lowEfficiencyMinClicksKey) as? Int
            return stored ?? AnalyticsConfiguration.lowEfficiencyMinClicks
        }
        set {
            UserDefaults.standard.set(newValue, forKey: lowEfficiencyMinClicksKey)
        }
    }

    static var dataRetentionDays: Int {
        get {
            UserDefaults.standard.integer(forKey: dataRetentionDaysKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: dataRetentionDaysKey)
        }
    }

    static var lastRetentionPurgeDay: String? {
        get {
            UserDefaults.standard.string(forKey: lastRetentionPurgeDayKey)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: lastRetentionPurgeDayKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastRetentionPurgeDayKey)
            }
        }
    }

    static func notifyDashboardSettingsDidChange() {
        NotificationCenter.default.post(name: .dashboardSettingsDidChange, object: nil)
    }
}
