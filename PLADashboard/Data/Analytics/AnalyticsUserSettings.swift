import Foundation

/// 用户可在设置页调整的分析阈值快照；其余规则仍使用 `AnalyticsConfiguration` 静态默认值。
struct AnalyticsSettingsSnapshot: Sendable, Hashable {
    var highEfficiencyROIMultiplier: Double
    var lowEfficiencyMinClicks: Int

    static let defaults = AnalyticsSettingsSnapshot(
        highEfficiencyROIMultiplier: AnalyticsConfiguration.highEfficiencyROIMultiplier,
        lowEfficiencyMinClicks: AnalyticsConfiguration.lowEfficiencyMinClicks
    )

    static func current(accountID: String) -> AnalyticsSettingsSnapshot {
        AnalyticsSettingsSnapshot(
            highEfficiencyROIMultiplier: AppSettings.highEfficiencyROIMultiplier(accountID: accountID),
            lowEfficiencyMinClicks: AppSettings.lowEfficiencyMinClicks(accountID: accountID)
        )
    }
}
