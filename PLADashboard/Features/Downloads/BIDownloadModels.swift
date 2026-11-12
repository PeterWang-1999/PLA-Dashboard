import Foundation

enum BIReportCalendar {
    static let timeZone = TimeZone(identifier: "Asia/Shanghai")!

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 1
        return calendar
    }

    static func weeks(through now: Date, count: Int) -> [BIReportWeek] {
        let calendar = self.calendar
        guard let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        return (0..<count).compactMap { offset in
            calendar.date(byAdding: .weekOfYear, value: -offset, to: start).map(BIReportWeek.init)
        }
    }

    static func occurrence(hour: Int, minute: Int, near date: Date, next: Bool) -> Date? {
        let calendar = self.calendar
        let day = calendar.startOfDay(for: date)
        guard let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { return nil }
        if next { return today > date ? today : calendar.date(byAdding: .day, value: 1, to: today) }
        return today <= date ? today : calendar.date(byAdding: .day, value: -1, to: today)
    }
}

struct BIReportWeek: Identifiable {
    let start: Date
    var id: String {
        var format = Date.FormatStyle(date: .numeric, time: .omitted, locale: Locale(identifier: "en_CA"))
        format.timeZone = BIReportCalendar.timeZone
        let day = BIReportCalendar.calendar.dateComponents([.year, .month, .day], from: start)
        let key = String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
        return WeekCalendar.plaWeekLabel(forWeekStartDay: key) ?? format.format(start)
    }

    var end: Date { BIReportCalendar.calendar.date(byAdding: .day, value: 6, to: start) ?? start }
}

enum BIDimension: String, Codable, CaseIterable, Identifiable {
    case date = "日期"
    case country = "国家"
    case category2 = "二级品类"
    case category3 = "三级品类"

    var id: Self { self }
}

enum BIClassification: String, Codable {
    case businessUnit
    case category
}

struct BIFilters: Codable, Equatable {
    var channel = "Google PLA"
    var businessUnit = "Toys & Hobbies"
    var category = ""
    var country = ""
    var firstWeek: String?
    var lastWeek: String?
    var dimensions = Set(BIDimension.allCases)
    var classification: BIClassification?
    var merchant: String?

    var classificationMode: BIClassification {
        classification ?? (category.isEmpty ? .businessUnit : .category)
    }

    func resolved(through now: Date) -> BIFilters {
        guard firstWeek == nil || lastWeek == nil else { return self }
        let weeks = BIReportCalendar.weeks(through: now, count: 7)
        var result = self
        result.firstWeek = weeks.last?.id
        result.lastWeek = weeks.first?.id
        return result
    }

    var weekLabel: String {
        [firstWeek, lastWeek].compactMap { $0 }.joined(separator: " – ")
    }

    var rangeRule: String {
        firstWeek == nil ? "过去 6 个完整周 + 本周" : weekLabel
    }
}

struct BIFilterOptions: Codable {
    var channels = ["Google PLA"]
    var businessUnits = ["Toys & Hobbies"]
    var categories: [String] = []
    var countries: [String] = []
    var reportWeeks: [String]?
    var merchants: [String]?
}

struct BIPreset: Codable, Identifiable {
    static let standard = BIPreset(
        id: "toys-google-pla",
        name: "Toys & Hobbies · Google PLA · 周报",
        filters: BIFilters()
    )

    var id: String = UUID().uuidString
    var name: String
    var filters: BIFilters
}

struct BISchedule: Codable, Identifiable {
    var id = UUID()
    var name = BIPreset.standard.name
    var presetID = BIPreset.standard.id
    var hour = 18
    var minute = 30
    var enabled = true
    var nextRun: Date?

    var timeLabel: String { String(format: "%02d:%02d", hour, minute) }

    mutating func updateNextRun(after date: Date) {
        nextRun = enabled ? BIReportCalendar.occurrence(hour: hour, minute: minute, near: date, next: true) : nil
    }
}

struct BIDownloadRun: Codable, Identifiable {
    enum Origin: String, Codable {
        case scheduled = "定时下载"
        case manual = "临时导出"
    }

    enum Status: String, Codable {
        case queued, submitting, generating, downloading, completed, needsLogin, connectionFailed, failed
    }

    var id = UUID()
    let origin: Origin
    let filters: BIFilters
    let submittedAt: Date
    var status: Status = .queued
    var detail: String?
    var remoteTaskName: String { "渠道投放分析__PLA_\(id.uuidString)" }
}

struct BIWorkspace: Codable {
    var portal: URL?
    var options = BIFilterOptions()
    var presets = [BIPreset.standard]
    var schedules: [BISchedule] = []
    var runs: [BIDownloadRun] = []
}
