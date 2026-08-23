import SwiftUI
import Charts

private extension Color {
    /// Apple 官网日间模式的浅灰背景色 #F5F5F7。
    static let appleLightBackground = Color(red: 245.0 / 255.0, green: 245.0 / 255.0, blue: 247.0 / 255.0)
}

/// 趋势图时间粒度：周 / 日。
private enum TrendGranularity: String, CaseIterable {
    case weekly = "周维度"
    case daily = "日维度"
}

struct DataDashboardView: View {
    @Bindable var viewModel: DashboardViewModel
    let accountKind: WorkspaceAccountKind
    var onRequestDataUpdate: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trendGranularity: TrendGranularity = .weekly
    @State private var trendProgress: Double = 0

    var body: some View {
        Group {
            if let message = viewModel.dataDashboardErrorMessage {
                ContentUnavailableView {
                    Label("无法加载数据看板", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试") { Task { await viewModel.refreshDataDashboard() } }
                        .buttonStyle(.borderedProminent)
                }
            } else if viewModel.dataDashboardSnapshot.metrics.isEmpty,
                      !viewModel.isLoadingDataDashboard {
                ContentUnavailableView {
                    Label("暂无看板数据", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("导入投放数据后，这里会展示整体表现、趋势、类目与产品排行。")
                } actions: {
                    Button("数据更新", action: onRequestDataUpdate)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                dashboardContent
            }
        }
        .navigationTitle("数据看板")
        .toolbar { DashboardToolbarContent(viewModel: viewModel) }
        .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: "输入产品 ID 查询")
        .task(id: viewModel.makeCurrentFilters()) {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await viewModel.refreshDataDashboard()
        }
        .onChange(of: viewModel.searchText) { _, _ in viewModel.onSearchTextChanged() }
        .onChange(of: viewModel.selectedAlertFilter) { _, _ in viewModel.onFiltersChanged() }
        .onChange(of: viewModel.selectedCustomLabelFilter) { _, _ in viewModel.onFiltersChanged() }
        .onChange(of: viewModel.selectedCategoryFilter) { _, _ in viewModel.onFiltersChanged() }
    }

    private var snapshot: DataDashboardSnapshot { viewModel.dataDashboardSnapshot }

    /// 页面背景：日间使用 Apple 官网浅灰 #F5F5F7，夜间沿用系统窗口背景。
    private var pageBackground: Color {
        colorScheme == .dark ? Color(nsColor: .windowBackgroundColor) : .appleLightBackground
    }

    private var dashboardContent: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 28) {
                metricSection
                trendSection
                if accountKind == .thirdParty { campaignSection }
                categorySection
                productSection
            }
            .padding(24)
            .frame(maxWidth: 1_440, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(pageBackground)
        .overlay(alignment: .topTrailing) {
            if viewModel.isLoadingDataDashboard {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(12)
                    .accessibilityLabel("正在刷新数据看板")
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                if let label = snapshot.reportingPeriodLabel {
                    Label(label, systemImage: "calendar.badge.clock")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.bar)
        }
    }

    private var metricSection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
            ForEach(snapshot.metrics) { metric in
                DataDashboardMetricCard(metric: metric)
            }
        }
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text("消费、销售与 ROI 趋势")
                    .font(.title3.weight(.semibold))
                Spacer()
                Picker("趋势粒度", selection: $trendGranularity) {
                    ForEach(TrendGranularity.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                .onChange(of: trendGranularity) { _, newValue in
                    let animation: Animation = reduceMotion
                        ? .easeInOut(duration: 0.2)
                        : .spring(response: 0.45, dampingFraction: 0.82)
                    withAnimation(animation) {
                        trendProgress = newValue == .weekly ? 0 : 1
                    }
                }
            }
            MorphingComboTrendChart(
                weekly: snapshot.weeklyTrend,
                daily: snapshot.dailyTrend,
                progress: trendProgress
            )
        }
    }

    private var campaignSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "广告系列表现", detail: "仅三方站账户显示 · 按消费降序")
            CampaignPerformanceList(rows: snapshot.campaigns)
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "类目效率分布", detail: "横轴消费，纵轴 ROI，气泡大小代表销售额")
            CategoryBubbleChart(points: snapshot.categories)
        }
    }

    private var productSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "消费 Top 10 产品", detail: "当前筛选范围")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(Array(snapshot.topProducts.enumerated()), id: \.element.id) { index, product in
                    TopProductCard(rank: index + 1, product: product)
                }
            }
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private extension View {
    /// 卡片式表面：以系统控件背景色填充，叠加分隔线描边与柔和投影，
    /// 保证在日间/夜间两种外观下卡片边界与层级都清晰可见。
    func cardSurface(cornerRadius: CGFloat) -> some View {
        self
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 2)
    }
}

private struct DataDashboardMetricCard: View {
    let metric: DataDashboardMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Text(metric.reference)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text(metric.value)
                .font(.system(.largeTitle, weight: .semibold))
                .tracking(-0.5)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            HStack(spacing: 6) {
                if metric.comparisonDirection != .neutral {
                    Image(systemName: comparisonSymbol)
                        .accessibilityHidden(true)
                }
                Text(metric.comparison)
                    .monospacedDigit()
                Text(metric.comparisonLabel)
                    .fontWeight(.regular)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(comparisonColor)
        }
        .padding(16)
        .cardSurface(cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }

    private var comparisonSymbol: String {
        switch metric.comparisonDirection {
        case .positive: "arrowtriangle.up.fill"
        case .negative: "arrowtriangle.down.fill"
        case .neutral: "minus"
        }
    }

    private var comparisonColor: Color {
        switch metric.comparisonDirection {
        case .positive: .green
        case .negative: .red
        case .neutral: .secondary
        }
    }
}

private struct MorphingComboTrendChart: View {
    let weekly: [DataDashboardTrendPoint]
    let daily: [DataDashboardTrendPoint]
    /// 0 = 周维度，1 = 日维度。
    let progress: Double

    private struct MorphPoint: Identifiable {
        let id: Int
        let x: Double       // 槽位；过渡期日维度多出的点落在右侧边界之外
        let cost: Double    // 美元
        let sales: Double
        let roi: Double
    }

    private static let tickFractions: [Double] = [1.0, 0.75, 0.5, 0.25, 0.0]

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
        }
        .frame(width: plotW, height: plotH)
        .clipped()
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
        // 只连接已滑入绘图区的点，避免周维度时折线在右侧留出一段水平尾巴。
        let visible = points.filter { $0.x <= Double(slotCount) - 0.5 }
        func yPos(_ value: Double) -> CGFloat {
            CGFloat(1 - value / roiMax) * plotH
        }

        return ZStack {
            Path { path in
                for (index, point) in visible.enumerated() {
                    let location = CGPoint(x: xPosition(point.x, plotW: plotW), y: yPos(point.roi))
                    if index == 0 { path.move(to: location) } else { path.addLine(to: location) }
                }
            }
            .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            ForEach(visible) { point in
                Circle()
                    .fill(Color.green)
                    .frame(width: 5, height: 5)
                    .position(x: xPosition(point.x, plotW: plotW), y: yPos(point.roi))
            }
        }
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

private struct CampaignPerformanceList: View {
    let rows: [DataDashboardCampaignRow]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
            GridRow {
                Text("广告系列").gridColumnAlignment(.leading)
                Text("消费").gridColumnAlignment(.trailing)
                Text("ROI").gridColumnAlignment(.trailing)
                Text("CPC").gridColumnAlignment(.trailing)
                Text("CVR").gridColumnAlignment(.trailing)
                Text("AOS").gridColumnAlignment(.trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.vertical, 10)

            Divider().gridCellColumns(6)
            ForEach(rows) { row in
                GridRow {
                    Text(row.campaign).lineLimit(1).help(row.campaign)
                    Text(row.metrics.costCents, format: .currency(code: "USD").precision(.fractionLength(2)))
                    Text(row.metrics.roi, format: .number.precision(.fractionLength(2)))
                    Text(row.metrics.cpc, format: .currency(code: "USD").precision(.fractionLength(2)))
                    Text(row.metrics.cvr, format: .percent.precision(.fractionLength(2)))
                    Text(row.metrics.aos, format: .currency(code: "USD").precision(.fractionLength(2)))
                }
                .monospacedDigit()
                .padding(.vertical, 9)
                Divider().gridCellColumns(6)
            }
        }
        .padding(.horizontal, 14)
        .cardSurface(cornerRadius: 14)
        .accessibilityElement(children: .contain)
    }
}

private struct CategoryBubbleChart: View {
    let points: [DataDashboardCategoryPoint]

    var body: some View {
        Chart(points) { point in
            PointMark(
                x: .value("投放成本", Double(point.metrics.costCents) / 100),
                y: .value("ROI", point.metrics.roi)
            )
            .symbolSize(by: .value("销售额", max(1, Double(point.metrics.conversionValueCents) / 100)))
            .foregroundStyle(Color.accentColor.opacity(0.72))
            .annotation(position: .top, spacing: 4) {
                Text(point.category).font(.caption).lineLimit(1)
            }
        }
        .chartXAxisLabel("投放成本（USD）")
        .chartYAxisLabel("广告 ROI")
        .chartLegend(.hidden)
        .chartXScale(range: .plotDimension(padding: 34))
        .chartYScale(range: .plotDimension(padding: 24))
        .frame(height: 380)
        .accessibilityLabel("类目消费、ROI 与销售额气泡图")
    }
}

private struct TopProductCard: View {
    let rank: Int
    let product: DataDashboardProduct

    var body: some View {
        HStack(spacing: 12) {
            ProductImageView(imageURL: product.imageURL, size: 72)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(product.title).font(.headline).lineLimit(1)
                    Spacer()
                    Text("#\(rank)").font(.caption.weight(.semibold)).foregroundStyle(.tint)
                }
                Text(product.productID).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                    GridRow { Text("消费").foregroundStyle(.secondary); Text(product.metrics.costCents, format: .currency(code: "USD")) }
                    GridRow { Text("销售").foregroundStyle(.secondary); Text(product.metrics.conversionValueCents, format: .currency(code: "USD")) }
                    GridRow { Text("ROI").foregroundStyle(.secondary); Text(product.metrics.roi, format: .number.precision(.fractionLength(2))) }
                }
                .font(.caption)
                .monospacedDigit()
            }
        }
        .padding(12)
        .cardSurface(cornerRadius: 14)
        .accessibilityElement(children: .combine)
    }
}
