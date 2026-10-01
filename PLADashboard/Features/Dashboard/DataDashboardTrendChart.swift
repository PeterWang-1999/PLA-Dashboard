import SwiftUI
import AppKit

/// 把旧、新两组趋势按 `progress`（0 = 旧，1 = 新）逐点插值。
/// 周/日维度周期固定，仅数值随筛选变化，因此可按元素一一对应地过渡。
private func interpolatedTrend(
    from: [DataDashboardTrendPoint],
    to: [DataDashboardTrendPoint],
    progress: Double
) -> [DataDashboardTrendPoint] {
    guard from.count == to.count else { return to }
    if progress <= 0 { return from }
    if progress >= 1 { return to }
    return zip(from, to).map { old, new in
        DataDashboardTrendPoint(
            period: new.period,
            displayLabel: new.displayLabel,
            costCents: interpolateCents(old.costCents, new.costCents, progress),
            salesCents: interpolateCents(old.salesCents, new.salesCents, progress),
            roi: old.roi + (new.roi - old.roi) * progress,
            cvr: old.cvr + (new.cvr - old.cvr) * progress,
            cpc: old.cpc + (new.cpc - old.cpc) * progress,
            aos: old.aos + (new.aos - old.aos) * progress
        )
    }
}
private func interpolateCents(_ from: Int, _ to: Int, _ progress: Double) -> Int {
    from + Int((Double(to - from) * progress).rounded())
}

/// 工具栏筛选（自定义标签/类目）变化时，让趋势图以与周/日切换相同的
/// 弹性动画从旧数据过渡到新数据。通过 `Animatable` 让 `filterProgress` 逐帧插值，
/// 再调用 `interpolatedTrend` 生成中间帧数据，交给 `MorphingComboTrendChart` 渲染。
/// 周/日维度进度由内层图表自身的 `Animatable` 负责，二者互不干扰。
struct FilterMorphingTrendChart: View, Animatable {
    let fromWeekly: [DataDashboardTrendPoint]
    let fromDaily: [DataDashboardTrendPoint]
    let toWeekly: [DataDashboardTrendPoint]
    let toDaily: [DataDashboardTrendPoint]
    /// 周/日维度进度，直接透传给内层图表。
    let granularityProgress: Double
    /// 0 = 旧（筛选前）数据，1 = 新（筛选后）数据。
    var filterProgress: Double

    var animatableData: Double {
        get { filterProgress }
        set { filterProgress = newValue }
    }

    var body: some View {
        MorphingComboTrendChart(
            weekly: interpolatedTrend(from: fromWeekly, to: toWeekly, progress: filterProgress),
            daily: interpolatedTrend(from: fromDaily, to: toDaily, progress: filterProgress),
            progress: granularityProgress
        )
    }
}

private struct MorphingComboTrendChart: View, Animatable {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let weekly: [DataDashboardTrendPoint]
    let daily: [DataDashboardTrendPoint]
    /// 0 = 周维度，1 = 日维度。
    var progress: Double

    /// 当前悬停命中的周期及其相邻上一周期（用于环比）。
    @State private var hovered: TrendHoverTarget?

    /// 让 `progress` 参与 SwiftUI 动画事务：`withAnimation` 切换周/日时，系统逐帧插值
    /// `animatableData` 并重绘整个图表，使 `Path` 绘制的 ROI 曲线与柱状体一起平滑过渡。
    /// `Path` 本身没有可动画数据，若不参与则曲线会在切换瞬间直接跳到终态。
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    /// 悬停目标：命中的周期点、其上一周期点（环比基准）与绘图区横坐标（引导线位置）。
    private struct TrendHoverTarget {
        let point: DataDashboardTrendPoint
        let previous: DataDashboardTrendPoint?
        let x: CGFloat
    }

    private struct MorphPoint: Identifiable {
        let id: Int
        let x: Double       // 槽位；过渡期日维度多出的点落在右侧边界之外
        let cost: Double    // 美元
        let sales: Double
        let roi: Double
    }

    private static let tickFractions: [Double] = [1.0, 0.75, 0.5, 0.25, 0.0]

    private static let utcGregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static let weekRangeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd"
        return formatter
    }()

    private var slotCount: Int { max(weekly.count, daily.count, 1) }

    /// 把某个数据集的第 index 个点均匀铺到整条坐标轴上（0 … slotCount-1）。
    /// 点数较少的周维度会铺满整条轴，切换时再「收拢」到左侧，为从右侧滑入的日维度点让位。
    private func spreadX(index: Int, count: Int) -> Double {
        count > 1 ? Double(index) * Double(slotCount - 1) / Double(count - 1) : 0
    }

    /// 槽位坐标 → 绘图区横坐标（像素）。
    private func xPosition(_ x: Double, plotW: CGFloat) -> CGFloat {
        let range = -0.5 ... Double(slotCount) - 0.5
        let t = (x - range.lowerBound) / (range.upperBound - range.lowerBound)
        return CGFloat(t) * plotW
    }

    /// 图形在周 / 日之间持续存在并平滑移动；日维度多出的点从右侧滑入。
    private var points: [MorphPoint] {
        guard !weekly.isEmpty || !daily.isEmpty else { return [] }
        let w = weekly.count
        let d = daily.count
        let n = slotCount
        let lastWeeklyROI = w > 0 ? weekly[w - 1].roi : 0
        return (0..<n).map { i in
            let wCost = i < w ? Double(weekly[i].costCents) / 100 : 0
            let wSales = i < w ? Double(weekly[i].salesCents) / 100 : 0
            let wROI = i < w ? weekly[i].roi : lastWeeklyROI
            let dCost = i < d ? Double(daily[i].costCents) / 100 : 0
            let dSales = i < d ? Double(daily[i].salesCents) / 100 : 0
            let dROI = i < d ? daily[i].roi : lastWeeklyROI

            if i < w {
                let fromX = spreadX(index: i, count: w)
                let toX = spreadX(index: i, count: d)
                return MorphPoint(
                    id: i,
                    x: fromX + (toX - fromX) * progress,
                    cost: wCost + (dCost - wCost) * progress,
                    sales: wSales + (dSales - wSales) * progress,
                    roi: wROI + (dROI - wROI) * progress
                )
            }
            let toX = spreadX(index: i, count: d)
            let startX = Double(n) + 0.5
            return MorphPoint(
                id: i,
                x: startX + (toX - startX) * progress,
                cost: dCost * progress,
                sales: dSales * progress,
                roi: wROI + (dROI - wROI) * progress
            )
        }
    }

    private var weeklyMaxAmount: Double {
        weekly.map { max(Double($0.costCents), Double($0.salesCents)) / 100 }.max() ?? 0
    }
    private var dailyMaxAmount: Double {
        daily.map { max(Double($0.costCents), Double($0.salesCents)) / 100 }.max() ?? 0
    }
    private var currentMaxAmount: Double {
        weeklyMaxAmount + (dailyMaxAmount - weeklyMaxAmount) * progress
    }
    private var weeklyMaxROI: Double { weekly.map(\.roi).max() ?? 0 }
    private var dailyMaxROI: Double { daily.map(\.roi).max() ?? 0 }
    private var currentMaxROI: Double {
        weeklyMaxROI + (dailyMaxROI - weeklyMaxROI) * progress
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                chartLegend
            }
            chartBody
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("消费销售和 ROI 组合图")
        .onDisappear { TrendHoverPanelController.shared.hide() }
    }

    private var chartBody: some View {
        GeometryReader { geo in
            let size = geo.size
            let leftAxisW: CGFloat = 64
            let rightAxisW: CGFloat = 50
            let bottomH: CGFloat = 24
            let plotW = max(0, size.width - leftAxisW - rightAxisW)
            let plotH = max(0, size.height - bottomH)

            ZStack(alignment: .topLeading) {
                plotView(plotW: plotW, plotH: plotH)
                    .position(x: leftAxisW + plotW / 2, y: plotH / 2)

                ForEach(Self.tickFractions, id: \.self) { fraction in
                    Text(amountString(currentMaxAmount * fraction))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .position(x: leftAxisW / 2, y: plotH * CGFloat(1 - fraction))
                }

                ForEach(Self.tickFractions, id: \.self) { fraction in
                    Text(roiString(currentMaxROI * fraction))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .position(x: leftAxisW + plotW + rightAxisW / 2, y: plotH * CGFloat(1 - fraction))
                }

                xAxisLabels(plotW: plotW)
                    .position(x: leftAxisW + plotW / 2, y: plotH + bottomH / 2)
            }
            .frame(width: size.width, height: size.height)
        }
        .frame(height: 300)
    }

    private func plotView(plotW: CGFloat, plotH: CGFloat) -> some View {
        ZStack {
            gridLines(plotW: plotW, plotH: plotH)
            bars(plotW: plotW, plotH: plotH)
            roiLine(plotW: plotW, plotH: plotH)
            if let hovered {
                hoverGuide(x: hovered.x, plotH: plotH)
            }
        }
        .frame(width: plotW, height: plotH)
        .clipped()
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case let .active(location):
                updateHover(at: location, plotW: plotW)
            case .ended:
                hovered = nil
                TrendHoverPanelController.shared.hide()
            }
        }
    }

    private func gridLines(plotW: CGFloat, plotH: CGFloat) -> some View {
        ForEach(Self.tickFractions, id: \.self) { fraction in
            let y = plotH * CGFloat(1 - fraction)
            Path { path in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: plotW, y: y))
            }
            .stroke(.quaternary, lineWidth: 1)
        }
    }

    private func bars(plotW: CGFloat, plotH: CGFloat) -> some View {
        let slotWidth = plotW / CGFloat(slotCount)
        let barWidth = slotWidth * 0.34
        let amountMax = max(currentMaxAmount, 0.0001)
        func barHeight(_ value: Double) -> CGFloat {
            max(0, CGFloat(value / amountMax) * plotH)
        }

        return ZStack {
            ForEach(points) { point in
                let cx = xPosition(point.x, plotW: plotW)
                let costHeight = barHeight(point.cost)
                let salesHeight = barHeight(point.sales)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: barWidth, height: costHeight)
                    .position(x: cx - barWidth / 2, y: plotH - costHeight / 2)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.orange)
                    .frame(width: barWidth, height: salesHeight)
                    .position(x: cx + barWidth / 2, y: plotH - salesHeight / 2)
            }
        }
    }

    private func roiLine(plotW: CGFloat, plotH: CGFloat) -> some View {
        let roiMax = max(currentMaxROI, 0.0001)
        // 只连接已滑入绘图区的点，避免周维度时曲线在右侧留出一段水平尾巴。
        let visible = points.filter { $0.x <= Double(slotCount) - 0.5 }
        func yPos(_ value: Double) -> CGFloat {
            CGFloat(1 - value / roiMax) * plotH
        }

        let locations = visible.map {
            CGPoint(x: xPosition($0.x, plotW: plotW), y: yPos($0.roi))
        }

        return ZStack {
            smoothPath(locations)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            ForEach(visible) { point in
                Circle()
                    .fill(Color.green)
                    .frame(width: 5, height: 5)
                    .position(x: xPosition(point.x, plotW: plotW), y: yPos(point.roi))
            }
        }
    }

    /// Catmull-Rom 样条：把离散 ROI 点连成平滑曲线，取代折线的硬切拐角（两端夹紧）。
    private func smoothPath(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        guard pts.count > 2 else {
            path.move(to: first)
            for p in pts.dropFirst() { path.addLine(to: p) }
            return path
        }
        path.move(to: first)
        let control = [first] + pts + [pts[pts.count - 1]]
        let subdivisions = 20
        for i in 0..<(pts.count - 1) {
            let p0 = control[i]
            let p1 = control[i + 1]
            let p2 = control[i + 2]
            let p3 = control[i + 3]
            for step in 1...subdivisions {
                let t = CGFloat(step) / CGFloat(subdivisions)
                let t2 = t * t
                let t3 = t2 * t
                let x = 0.5 * (2 * p1.x + (-p0.x + p2.x) * t
                    + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2
                    + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
                let y = 0.5 * (2 * p1.y + (-p0.y + p2.y) * t
                    + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2
                    + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }

    /// 在绘图区内命中最近的数据点（按像素距离），返回其在对应序列中的下标。
    private func nearestPointIndex(in series: [DataDashboardTrendPoint], forX px: CGFloat, plotW: CGFloat) -> Int {
        var best = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for i in series.indices {
            let pointX = xPosition(spreadX(index: i, count: series.count), plotW: plotW)
            let distance = abs(pointX - px)
            if distance < bestDistance {
                bestDistance = distance
                best = i
            }
        }
        return best
    }

    /// 处理持续悬停：命中当前粒度的最近周期，更新引导线并弹出浮动详情。
    private func updateHover(at location: CGPoint, plotW: CGFloat) {
        let isWeekly = progress < 0.5
        let series = isWeekly ? weekly : daily
        guard !series.isEmpty else {
            hovered = nil
            TrendHoverPanelController.shared.hide()
            return
        }
        let index = nearestPointIndex(in: series, forX: location.x, plotW: plotW)
        let point = series[index]
        let previous = index > 0 ? series[index - 1] : nil
        let pixelX = xPosition(spreadX(index: index, count: series.count), plotW: plotW)
        let target = TrendHoverTarget(point: point, previous: previous, x: pixelX)
        hovered = target
        TrendHoverPanelController.shared.show(
            id: "combo-trend-\(isWeekly ? "w" : "d")-\(point.period)",
            at: NSEvent.mouseLocation,
            content: AnyView(trendHoverPanel(for: target, isWeekly: isWeekly))
        )
    }

    private func hoverGuide(x: CGFloat, plotH: CGFloat) -> some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.22))
            .frame(width: 1, height: plotH)
            .position(x: x, y: plotH / 2)
    }

    private func trendHoverPanel(for target: TrendHoverTarget, isWeekly: Bool) -> some View {
        let point = target.point
        let previous = target.previous
        return VStack(alignment: .leading, spacing: 6) {
            Text(point.displayLabel).font(.headline)
            Text(periodSubtitle(point, isWeekly: isWeekly))
                .font(.caption)
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("消费").foregroundStyle(.secondary)
                    Text(DashboardMetricFormatter.formatCurrencyFromCents(point.costCents)).monospacedDigit()
                }
                GridRow {
                    Text("销售").foregroundStyle(.secondary)
                    Text(DashboardMetricFormatter.formatCurrencyFromCents(point.salesCents)).monospacedDigit()
                }
                GridRow {
                    Text("ROI").foregroundStyle(.secondary)
                    Text(DashboardMetricFormatter.formatDecimal(point.roi, fractionDigits: 2)).monospacedDigit()
                }
                GridRow {
                    Text("CVR").foregroundStyle(.secondary)
                    HStack(spacing: 5) {
                        Text(DashboardMetricFormatter.formatPercentValue(point.cvr))
                        deltaLabel(point.cvr, previous?.cvr, inverted: false)
                    }
                    .monospacedDigit()
                }
                GridRow {
                    Text("CPC").foregroundStyle(.secondary)
                    HStack(spacing: 5) {
                        Text(DashboardMetricFormatter.formatDecimal(point.cpc))
                        deltaLabel(point.cpc, previous?.cpc, inverted: true)
                    }
                    .monospacedDigit()
                }
                GridRow {
                    Text("AOS").foregroundStyle(.secondary)
                    HStack(spacing: 5) {
                        Text(DashboardMetricFormatter.formatDecimal(point.aos))
                        deltaLabel(point.aos, previous?.aos, inverted: false)
                    }
                    .monospacedDigit()
                }
            }
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            reduceTransparency
                ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
                : AnyShapeStyle(.regularMaterial),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.separator.opacity(0.65), lineWidth: 0.5)
        }
        .padding(8)
        .fixedSize()
    }

    /// 环比标签：正值绿（改善）、负值红（恶化）；CPC 越低越好，故 `inverted` 反转配色。
    @ViewBuilder
    private func deltaLabel(_ value: Double, _ previous: Double?, inverted: Bool) -> some View {
        if let delta = relativeDelta(value, previous) {
            Text(formatDelta(delta))
                .foregroundStyle(deltaColor(delta, inverted: inverted))
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }

    private func relativeDelta(_ value: Double, _ previous: Double?) -> Double? {
        guard let previous, previous != 0 else { return nil }
        return (value - previous) / abs(previous)
    }

    private func formatDelta(_ delta: Double) -> String {
        String(format: "%+.1f%%", delta * 100)
    }

    private func deltaColor(_ delta: Double, inverted: Bool) -> Color {
        if delta == 0 { return .secondary }
        let improving = inverted ? delta < 0 : delta > 0
        return improving ? .green : .red
    }

    private func periodSubtitle(_ point: DataDashboardTrendPoint, isWeekly: Bool) -> String {
        guard isWeekly,
              let start = WeekCalendar.parseDay(point.period),
              let end = Self.utcGregorian.date(byAdding: .day, value: 6, to: start) else {
            return point.period
        }
        return "\(Self.weekRangeFormatter.string(from: start)) – \(Self.weekRangeFormatter.string(from: end))"
    }

    private func xAxisLabels(plotW: CGFloat) -> some View {
        ZStack {
            ForEach(weekly.indices, id: \.self) { index in
                Text(weekly[index].displayLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .position(x: xPosition(spreadX(index: index, count: weekly.count), plotW: plotW), y: 8)
                    .opacity(1 - progress)
            }
            ForEach(daily.indices, id: \.self) { index in
                Text(daily[index].displayLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .position(x: xPosition(spreadX(index: index, count: daily.count), plotW: plotW), y: 8)
                    .opacity(progress)
            }
        }
        .frame(width: plotW, height: 16)
    }

    private var chartLegend: some View {
        HStack(spacing: 14) {
            Label("消费", systemImage: "square.fill").foregroundStyle(Color.accentColor)
            Label("销售", systemImage: "square.fill").foregroundStyle(Color.orange)
            Label("ROI", systemImage: "line.diagonal").foregroundStyle(Color.green)
        }
        .font(.caption)
        .labelStyle(.titleAndIcon)
    }

    private func amountString(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    private func roiString(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }
}
