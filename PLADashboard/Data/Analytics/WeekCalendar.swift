import Foundation

/// 分析配置；`highEfficiencyROIMultiplier` 预留阶段 6 设置页可调。
enum AnalyticsConfiguration: Sendable {
    static let reportingWeekCount = 6
    static let consumptionLookbackWeeks = 3
    static let lowEfficiencyMinClicks = 300
    static let highSpendDailyMultiplier = 5.0
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

    /// 以 `endDate` 所在周为最近一周，返回由旧到新的 `reportingWeekCount` 个 `week_start`。
    static func reportingWeekStarts(endingAt endDate: Date, count: Int = AnalyticsConfiguration.reportingWeekCount) -> [String] {
        let latestWeekStart = weekStartSunday(for: endDate)
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
