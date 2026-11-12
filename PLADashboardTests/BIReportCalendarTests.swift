import Foundation
import Testing
@testable import PLADashboard

struct BIReportCalendarTests {
    @Test func scheduledRunCreatesBothFilesWithTheSameResolvedFilters() {
        let date = Date(timeIntervalSinceReferenceDate: 816_161_000)
        let filters = BIFilters().resolved(through: date)
        let runs = BIDownloadRun.batch(origin: .scheduled, filters: filters, createdAt: date)
        #expect(runs.map(\.reportKind) == [.channelAnalysis, .productDetail])
        #expect(runs.map(\.reportKind.fileExtension) == ["csv", "xlsx"])
        #expect(runs.allSatisfy { $0.filters == filters && $0.submittedAt == date })
        #expect(Set(runs.map(\.id)).count == 2)
        #expect(BIDownloadRun.batch(origin: .manual, filters: filters, createdAt: date)
            .map(\.reportKind) == [.channelAnalysis])
    }

    @Test func existingRunKeepsItsOriginalReportAndRemoteName() throws {
        let source = """
        {
          "id": "11111111-2222-4333-8444-555555555555",
          "origin": "定时下载",
          "filters": {
            "channel": "Google PLA", "businessUnit": "Toys & Hobbies",
            "category": "", "country": "", "dimensions": ["日期"]
          },
          "submittedAt": 816161000,
          "status": "completed"
        }
        """
        let run = try JSONDecoder().decode(BIDownloadRun.self, from: Data(source.utf8))
        #expect(run.reportKind == .channelAnalysis)
        #expect(run.remoteTaskName == "渠道投放分析__PLA_11111111-2222-4333-8444-555555555555")
    }

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
