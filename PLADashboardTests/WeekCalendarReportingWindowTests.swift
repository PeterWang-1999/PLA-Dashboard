import XCTest
@testable import PLADashboard

final class WeekCalendarReportingWindowTests: XCTestCase {
    func testLastCompleteWeekEndOnSaturdayIsUnchanged() throws {
        let saturday = try XCTUnwrap(WeekCalendar.parseDay("2026-07-04"))
        let end = WeekCalendar.lastCompleteWeekEnd(onOrBefore: saturday)
        XCTAssertEqual(WeekCalendar.formatDay(end), "2026-07-04")
    }

    func testLastCompleteWeekEndOnWednesdaySnapsToPriorSaturday() throws {
        // 明细导出常含不完整最新周（如 07-05..07-08）；报告锚点应回退到上一周六。
        let wednesday = try XCTUnwrap(WeekCalendar.parseDay("2026-07-08"))
        let end = WeekCalendar.lastCompleteWeekEnd(onOrBefore: wednesday)
        XCTAssertEqual(WeekCalendar.formatDay(end), "2026-07-04")
    }

    func testLastCompleteWeekEndOnSundaySnapsToPriorSaturday() throws {
        let sunday = try XCTUnwrap(WeekCalendar.parseDay("2026-07-05"))
        let end = WeekCalendar.lastCompleteWeekEnd(onOrBefore: sunday)
        XCTAssertEqual(WeekCalendar.formatDay(end), "2026-07-04")
    }

    func testReportingWeekStartsIgnoresIncompleteLatestWeek() throws {
        // 数据最新日 2026-07-08（周三）时，6 个完整报告周应为 W22–W27：
        // 2026-05-24 … 2026-06-28（与标签汇总 Cost_6w 窗口一致）。
        let latestDay = try XCTUnwrap(WeekCalendar.parseDay("2026-07-08"))
        let weeks = WeekCalendar.reportingWeekStarts(endingAt: latestDay)
        XCTAssertEqual(
            weeks,
            [
                "2026-05-24",
                "2026-05-31",
                "2026-06-07",
                "2026-06-14",
                "2026-06-21",
                "2026-06-28",
            ]
        )
    }

    func testReportingWeekStartsWhenLatestDayIsSaturday() throws {
        let saturday = try XCTUnwrap(WeekCalendar.parseDay("2026-07-04"))
        let weeks = WeekCalendar.reportingWeekStarts(endingAt: saturday)
        XCTAssertEqual(
            weeks,
            [
                "2026-05-24",
                "2026-05-31",
                "2026-06-07",
                "2026-06-14",
                "2026-06-21",
                "2026-06-28",
            ]
        )
    }

    /// 复现 S9730219：错误窗口 5229.74 vs 完整 6 周 6560.20（全量 6984.70 含不完整第 7 周）。
    func testS9730219SixWeekCostMatchesCompleteWindowNotPartial() {
        let costByWeekStart: [String: Double] = [
            "2026-05-24": 1754.96,
            "2026-05-31": 1411.11,
            "2026-06-07": 1094.64,
            "2026-06-14": 1000.22,
            "2026-06-21": 740.95,
            "2026-06-28": 558.32,
            "2026-07-05": 424.50,
        ]
        let allCost = costByWeekStart.values.reduce(0, +)
        XCTAssertEqual(allCost, 6984.70, accuracy: 0.01)

        let latestDay = WeekCalendar.parseDay("2026-07-08")!
        let completeWeeks = WeekCalendar.reportingWeekStarts(endingAt: latestDay)
        let completeCost = completeWeeks.map { costByWeekStart[$0] ?? 0 }.reduce(0, +)
        XCTAssertEqual(completeCost, 6560.20, accuracy: 0.01)

        // 旧逻辑：以最新日所在周为锚 → 丢掉 05-24 周、纳入不完整 07-05 周
        let buggyWeeks = [
            "2026-05-31",
            "2026-06-07",
            "2026-06-14",
            "2026-06-21",
            "2026-06-28",
            "2026-07-05",
        ]
        let buggyCost = buggyWeeks.map { costByWeekStart[$0] ?? 0 }.reduce(0, +)
        XCTAssertEqual(buggyCost, 5229.74, accuracy: 0.01)
        XCTAssertNotEqual(completeCost, buggyCost, accuracy: 0.01)
    }

    func testPlaWeekLabelUsesISOWeekOfSaturday() {
        XCTAssertEqual(WeekCalendar.plaWeekLabel(forWeekStartDay: "2026-05-24"), "2026-W22")
        XCTAssertEqual(WeekCalendar.plaWeekLabel(forWeekStartDay: "2026-06-28"), "2026-W27")
    }

    func testReportingPeriodLabelFormatsWeekRange() {
        let weeks = [
            "2026-05-24",
            "2026-05-31",
            "2026-06-07",
            "2026-06-14",
            "2026-06-21",
            "2026-06-28",
        ]
        XCTAssertEqual(
            WeekCalendar.reportingPeriodLabel(weekStarts: weeks),
            "当前报告周期：2026-W22 至 2026-W27"
        )
    }
}
