import Foundation
import Testing
@testable import PLADashboard

struct BIReportCalendarTests {
    @Test func presetResolvesSevenBIWeeksIncludingCurrentWeek() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-12T06:00:00Z"))
        let range = BIPreset.standard.filters.resolved(through: now)
        #expect(range.firstWeek == "2026-W40")
        #expect(range.lastWeek == "2026-W46")
        #expect(BIPreset.standard.filters.firstWeek == nil)
    }

    @Test func usesBeijingSundayAndBIWeekYear() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2027-01-02T16:00:00Z"))
        let range = BIPreset.standard.filters.resolved(through: now)
        #expect(range.firstWeek == "2026-W48")
        #expect(range.lastWeek == "2027-W01")
    }

    @Test func savedRangeRemainsFixedAndDailyScheduleUsesBeijingTime() throws {
        let formatter = ISO8601DateFormatter()
        let now = try #require(formatter.date(from: "2026-11-12T10:30:00Z"))
        var filters = BIFilters()
        filters.firstWeek = "2026-W42"
        filters.lastWeek = "2026-W46"
        #expect(filters.resolved(through: now) == filters)

        var schedule = BISchedule()
        schedule.updateNextRun(after: now)
        #expect(schedule.nextRun == formatter.date(from: "2026-11-13T10:30:00Z"))
        schedule.enabled = false
        schedule.updateNextRun(after: now)
        #expect(schedule.nextRun == nil)
    }
}
