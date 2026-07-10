import Foundation

/// 分析配置；高效倍数与低效点击门槛可在设置页调整（`AnalyticsSettingsSnapshot`）。
enum AnalyticsConfiguration: Sendable {
    static let reportingWeekCount = 6
    static let consumptionLookbackWeeks = 3
    static let lowEfficiencyMinClicks = 300
    static let lowEfficiencyWeeklyUnderperformWeeks = 2
    /// 低消费：日均消费 < max(此绝对门槛, lowSpendRatio × 当周 cohort 中位数日均)
    static let lowSpendAbsoluteFloorDailyCents = 300
    static let lowSpendRatio = 0.5
    /// 高消费：近 3 周每周日均 > highSpendMeanRatio × cohort 均值日均，且 6 周消费占比 ≥ highSpendMinCostShare
    static let highSpendMeanRatio = 2.5
    static let highSpendMinCostShare = 0.005
    static let efficiencyMinClicks = 100
    static let efficiencyMinConversions = 3.0
    /// 高效判定：产品加权 ROI > multiplier × 整体加权 ROI
    static let highEfficiencyROIMultiplier = 1.6
    /// 由旧到新，共 6 周
    static let roiWeekWeights: [Double] = [0.14, 0.15, 0.16, 0.17, 0.18, 0.20]
}

enum WeekCalendar {
    private static var sundayCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1
        return calendar
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = sundayCalendar
        formatter.timeZone = TimeZone(secondsFromGMT: 0)!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func parseDay(_ value: String) -> Date? {
        dayFormatter.date(from: value)
    }

    static func formatDay(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    /// 含该日在内所在周的周日（周起始日）。
    static func weekStartSunday(for date: Date) -> Date {
        let calendar = sundayCalendar
        let weekday = calendar.component(.weekday, from: date)
        let daysFromSunday = weekday - 1
        return calendar.date(byAdding: .day, value: -daysFromSunday, to: date) ?? date
    }

    static func weekStartSunday(forDay day: String) -> String? {
        guard let date = parseDay(day) else { return nil }
        return formatDay(weekStartSunday(for: date))
    }

    /// 不晚于 `date` 的最近一个周六（该自然周已完整：周日–周六）。
    ///
    /// 看板报告周必须以完整周为锚点：若最新数据日落在周中（如周三），
    /// 直接以该日所在周为「最近一周」会纳入不完整周并挤掉更早的完整周，
    /// 导致消费等 6 周汇总系统性偏低。
    static func lastCompleteWeekEnd(onOrBefore date: Date) -> Date {
        let calendar = sundayCalendar
        let weekday = calendar.component(.weekday, from: date) // 1=Sun … 7=Sat
        let daysBack = weekday % 7
        return calendar.date(byAdding: .day, value: -daysBack, to: date) ?? date
    }

    /// 以不晚于 `endDate` 的最近一个**完整周**为最近一周，返回由旧到新的 `reportingWeekCount` 个 `week_start`。
    static func reportingWeekStarts(endingAt endDate: Date, count: Int = AnalyticsConfiguration.reportingWeekCount) -> [String] {
        let completeWeekEnd = lastCompleteWeekEnd(onOrBefore: endDate)
        let latestWeekStart = weekStartSunday(for: completeWeekEnd)
        let calendar = sundayCalendar
        return (0..<count).reversed().compactMap { offset in
            guard let week = calendar.date(byAdding: .day, value: -7 * offset, to: latestWeekStart) else {
                return nil
            }
            return formatDay(week)
        }
    }

    static func microsToCents(_ micros: Int) -> Int {
        micros / 10_000
    }
}
