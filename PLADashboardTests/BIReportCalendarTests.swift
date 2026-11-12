import Foundation
import Testing
@testable import PLADashboard

struct BIReportCalendarTests {
    @Test func scheduledRunCreatesBothReportsWithTheSameResolvedWeeks() {
        let date = Date(timeIntervalSinceReferenceDate: 816_161_000)
        var filters = BIFilters().resolved(through: date)
        filters.dimensions = [.date]
        let runs = BIDownloadRun.batch(origin: .scheduled, filters: filters, createdAt: date)
        #expect(runs.map(\.reportKind) == [.channelAnalysis, .productDetail])
        #expect(runs.map(\.reportKind.fileExtension) == ["csv", "xlsx"])
        #expect(runs.first?.filters == filters)
        #expect(runs.last?.filters.firstWeek == filters.firstWeek)
        #expect(runs.last?.filters.lastWeek == filters.lastWeek)
        #expect(runs.last?.filters.productDetailThroughDay == nil)
        #expect(runs.last?.filters.dimensions == [.date, .country, .category2, .category3])
        #expect(runs.allSatisfy { $0.submittedAt == date })
        #expect(Set(runs.map(\.id)).count == 2)
        #expect(BIDownloadRun.batch(origin: .manual, filters: filters, createdAt: date)
            .map(\.reportKind) == [.channelAnalysis])
    }

    @Test func configuredCategoriesAreCombinedForChannelAndSplitForProductDetail() {
        let categories = [
            BICategory(id: "12", parentID: "1", level: 2, name: "Toys & Games", path: "Toys & Hobbies / Toys & Games"),
            BICategory(id: "13", parentID: "1", level: 2, name: "Pet Supplies", path: "Toys & Hobbies / Pet Supplies")
        ]
        var workspace = BIWorkspace()
        workspace.defaultCategories = categories
        let now = Date(timeIntervalSinceReferenceDate: 816_161_000)
        let filters = workspace.effectivePresets[0].filters.resolved(through: now)
        let scheduled = BIDownloadRun.batch(origin: .scheduled, filters: filters, createdAt: now)
        #expect(scheduled.map(\.reportKind) == [.channelAnalysis, .productDetail, .productDetail])
        #expect(scheduled.first?.filters.selectedCategories == categories)
        let sync = BIDownloadRun.batch(origin: .sync, filters: filters, createdAt: now)
        #expect(sync.map { $0.filters.selectedCategories?.map(\.id) ?? [] } == [["12"], ["12"], ["13"], ["13"]])
        #expect(sync.map(\.reportKind) == [.productDetail, .productSales, .productDetail, .productSales])
        #expect(sync.allSatisfy { $0.filters.productDetailThroughDay == BIReportCalendar.dayLabel(now) })
    }

    @Test func queuedScheduledProductDetailUsesWeeklyExportEvenWithAnOldDailyCutoff() throws {
        let data = Data("""
        {
          "origin": "定时下载",
          "report": "投放产品明细",
          "id": "11111111-2222-4333-8444-555555555555",
          "filters": {
            "channel": "Google PLA", "businessUnit": "Toys & Hobbies", "category": "", "country": "",
            "dimensions": ["日期"], "productDetailThroughDay": "2026-11-12"
          },
          "submittedAt": 816161000,
          "status": "queued"
        }
        """.utf8)
        let run = try JSONDecoder().decode(BIDownloadRun.self, from: data)
        #expect(run.reportKind == .productDetail)
        #expect(run.productDetailExportFilters.productDetailThroughDay == nil)
        #expect(run.productDetailExportFilters.dimensions == [.date, .country, .category2, .category3])
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
