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

    /// 趋势图使用的周：保留完整报告周，并在最新数据位于下一周时追加当前不完整周。
    static func trendWeekStarts(reportingWeekStarts: [String], latestDay: String) -> [String] {
        guard let currentWeekStart = weekStartSunday(forDay: latestDay) else {
            return reportingWeekStarts
        }
        return reportingWeekStarts.contains(currentWeekStart)
            ? reportingWeekStarts
            : reportingWeekStarts + [currentWeekStart]
    }

    /// 从周日到数据截止日（含首尾）的覆盖天数，限制在 1...7。
    static func coveredDayCount(weekStart: String, through latestDay: String) -> Int {
        guard let start = parseDay(weekStart), let end = parseDay(latestDay) else { return 7 }
        let days = sundayCalendar.dateComponents([.day], from: start, to: end).day ?? 6
        return min(7, max(1, days + 1))
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

    /// PLA 周标签：周日–周六自然周，按该周**周六**的 ISO 周年/周次格式化为 `yyyy-Www`（如 `2026-W22`）。
    ///
    /// 与业务汇总表 `week_mapping` 一致：`2026-05-24`（周日）起的周对应 `2026-W22`。
    static func plaWeekLabel(forWeekStartDay weekStart: String) -> String? {
        guard let start = parseDay(weekStart),
              let saturday = sundayCalendar.date(byAdding: .day, value: 6, to: start) else {
            return nil
        }
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = TimeZone(secondsFromGMT: 0)!
        let year = iso.component(.yearForWeekOfYear, from: saturday)
        let week = iso.component(.weekOfYear, from: saturday)
        return String(format: "%d-W%02d", year, week)
    }

    /// 报告周期文案，例如 `当前报告周期：2026-W22 至 2026-W27`。
    static func reportingPeriodLabel(weekStarts: [String]) -> String? {
        guard let first = weekStarts.first.flatMap(plaWeekLabel(forWeekStartDay:)),
              let last = weekStarts.last.flatMap(plaWeekLabel(forWeekStartDay:)) else {
            return nil
        }
        let range = first == last ? first : "\(first) 至 \(last)"
        return "当前报告周期：\(range)"
    }

    static func microsToCents(_ micros: Int) -> Int {
        micros / 10_000
    }
}
