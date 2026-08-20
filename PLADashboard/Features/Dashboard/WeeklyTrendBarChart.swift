import SwiftUI
import Charts
import AppKit

/// 表格单元格内的周趋势迷你柱状图：6 个完整周，并在有数据时追加当前周。
struct WeeklyTrendBarChart: View {
    enum Style {
        case cost
        case sales

        var barColor: Color { self == .cost ? Color.accentColor : Color.orange }
        var seriesName: String { self == .cost ? "消费" : "销售" }
        var barWidthRatio: CGFloat { self == .cost ? 0.82 : 0.88 }
    }

    let productID: String
    let values: [Int]
    let weekStarts: [String]
    let coverageDays: [Int]
    var style: Style = .cost

    @State private var hoveredWeekLabel: String?

    private struct WeekPoint: Identifiable {
        let weekLabel: String
        let weekStart: String
        let cents: Int
        let coveredDays: Int

        var id: String { weekLabel }
        var value: Double { Double(cents) / 100 }
        var isIncomplete: Bool { coveredDays < 7 }
    }

    private var points: [WeekPoint] {
        values.enumerated().map { index, cents in
            let weekStart = weekStarts.indices.contains(index) ? weekStarts[index] : ""
            return WeekPoint(
                weekLabel: WeekCalendar.plaWeekLabel(forWeekStartDay: weekStart) ?? "W\(index + 1)",
                weekStart: weekStart,
                cents: cents,
                coveredDays: coverageDays.indices.contains(index) ? coverageDays[index] : 7
            )
        }
    }

    private var hoveredPoint: WeekPoint? {
        points.first { $0.weekLabel == hoveredWeekLabel }
    }

    private var accessibilitySummary: String {
        guard points.contains(where: { $0.cents > 0 }) else { return "\(style.seriesName)趋势：无数据" }
        return points.map { point in
            "\(point.weekLabel) \(formattedAmount(point.cents))，日均 \(formattedAverage(point))"
                + (point.isIncomplete ? "，当周数据未完整" : "")
        }.joined(separator: "；")
    }

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Week", point.weekLabel),
                y: .value("Value", point.value),
                width: .ratio(style.barWidthRatio)
            )
            .foregroundStyle(style.barColor.opacity(point.isIncomplete ? 0.60 : 0.86))
            .cornerRadius(2)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(location):
                            guard let plotFrame = proxy.plotFrame else { return }
                            let plotOrigin = geometry[plotFrame].origin
                            let weekLabel = proxy.value(
                                atX: location.x - plotOrigin.x,
                                as: String.self
                            )
                            hoveredWeekLabel = weekLabel
                            if let weekLabel, let point = points.first(where: { $0.weekLabel == weekLabel }) {
                                TrendHoverPanelController.shared.show(
                                    id: "\(productID)-\(style.seriesName)-\(point.id)",
                                    at: NSEvent.mouseLocation,
                                    content: AnyView(trendDetail(for: point))
                                )
                            }
                        case .ended:
                            hoveredWeekLabel = nil
                            TrendHoverPanelController.shared.hide()
                        }
                    }
            }
        }
        .frame(minWidth: 58, idealWidth: 72, maxWidth: .infinity, minHeight: 28, idealHeight: 28, maxHeight: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .onDisappear { TrendHoverPanelController.shared.hide() }
    }

    private func trendDetail(for point: WeekPoint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(productID).font(.headline)
            Text(weekDescription(point)).font(.caption).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                GridRow {
                    Text("周\(style.seriesName)").foregroundStyle(.secondary)
                    Text(formattedAmount(point.cents)).monospacedDigit()
                }
                GridRow {
                    Text("日均\(style.seriesName)").foregroundStyle(.secondary)
                    Text(formattedAverage(point)).monospacedDigit()
                }
            }
            if point.isIncomplete {
                Label("当周数据未完整（\(point.coveredDays)/7 天）", systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.separator.opacity(0.65), lineWidth: 0.5)
        }
        .padding(8)
        .fixedSize()
    }

    private func weekDescription(_ point: WeekPoint) -> String {
        guard let start = WeekCalendar.parseDay(point.weekStart),
              let end = Calendar(identifier: .gregorian).date(byAdding: .day, value: point.coveredDays - 1, to: start) else {
            return point.weekLabel
        }
        return "\(point.weekLabel) · \(compactDay(start)) 至 \(compactDay(end))"
    }

    private func formattedAmount(_ cents: Int) -> String {
        DashboardMetricFormatter.formatCurrencyFromCents(cents)
    }

    private func formattedAverage(_ point: WeekPoint) -> String {
        let dailyCents = Double(point.cents) / Double(max(1, point.coveredDays))
        return DashboardMetricFormatter.formatDecimal(dailyCents / 100, fractionDigits: 2)
    }

    private func compactDay(_ date: Date) -> String {
        Self.compactDayFormatter.string(from: date)
    }

    private static let compactDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyMMdd"
        return formatter
    }()
}

/// SwiftUI 的 popover 固定带箭头；这个窄桥接仅负责承载不激活、忽略鼠标事件的跟随浮层。
@MainActor
private final class TrendHoverPanelController {
    static let shared = TrendHoverPanelController()

    private let panel: NSPanel
    private var contentID: String?

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = true
        panel.level = .floating
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
    }

    func show(id: String, at mouseLocation: NSPoint, content: AnyView) {
        if contentID != id {
            let hostingView = NSHostingView(rootView: content)
            hostingView.frame.size = hostingView.fittingSize
            panel.contentView = hostingView
            panel.setContentSize(hostingView.fittingSize)
            contentID = id
        }

        let offset = NSPoint(x: 14, y: 14)
        var origin = NSPoint(
            x: mouseLocation.x + offset.x,
            y: mouseLocation.y - panel.frame.height - offset.y
        )
        if let visibleFrame = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })?.visibleFrame {
            origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - panel.frame.width)
            if origin.y < visibleFrame.minY {
                origin.y = min(mouseLocation.y + offset.y, visibleFrame.maxY - panel.frame.height)
            }
        }
        panel.setFrameOrigin(origin)
        panel.orderFront(nil)
    }

    func hide() {
        panel.orderOut(nil)
        contentID = nil
    }
}
