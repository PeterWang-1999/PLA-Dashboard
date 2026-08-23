import SwiftUI
import Charts

struct DataDashboardView: View {
    @Bindable var viewModel: DashboardViewModel
    let accountKind: WorkspaceAccountKind
    var onRequestDataUpdate: () -> Void = {}

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
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "核心指标", detail: "随工具栏筛选同步")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                ForEach(snapshot.metrics) { metric in
                    DataDashboardMetricCard(metric: metric)
                }
            }
        }
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "消费、销售与 ROI 趋势", detail: "柱形为金额，折线使用右侧 ROI 坐标轴")
            ComboTrendChart(title: "周趋势", points: snapshot.weeklyTrend)
            ComboTrendChart(title: "近 14 日", points: snapshot.dailyTrend)
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
    /// 卡片式表面：以系统控件背景色填充，并叠加一条分隔线描边，
    /// 保证在日间/夜间两种外观下卡片边界都清晰可见。
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
    }
}

private struct DataDashboardMetricCard: View {
    let metric: DataDashboardMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(metric.title).font(.headline).foregroundStyle(.secondary)
                Spacer()
                Text(metric.reference).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(metric.value)
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            HStack {
                Text(metric.comparisonLabel).foregroundStyle(.secondary)
                Spacer()
                Text(metric.comparison)
                    .foregroundStyle(comparisonColor)
                    .monospacedDigit()
            }
            .font(.subheadline.weight(.medium))
        }
        .padding(18)
        .cardSurface(cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }

    private var comparisonColor: Color {
        switch metric.comparisonDirection {
        case .positive: .green
        case .negative: .red
        case .neutral: .secondary
        }
    }
}

private struct ComboTrendChart: View {
    let title: String
    let points: [DataDashboardTrendPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                chartLegend
            }
            ZStack {
                Chart(points) { point in
                    BarMark(
                        x: .value("周期", point.displayLabel),
                        y: .value("金额", Double(point.costCents) / 100),
                        width: .ratio(0.34)
                    )
                    .position(by: .value("系列", "消费"))
                    .foregroundStyle(by: .value("系列", "消费"))
                    .cornerRadius(4)

                    BarMark(
                        x: .value("周期", point.displayLabel),
                        y: .value("金额", Double(point.salesCents) / 100),
                        width: .ratio(0.34)
                    )
                    .position(by: .value("系列", "销售"))
                    .foregroundStyle(by: .value("系列", "销售"))
                    .cornerRadius(4)
                }
                .chartForegroundStyleScale(["消费": Color.accentColor, "销售": Color.orange])
                .chartLegend(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel {
                            if let amount = value.as(Double.self) { Text(amount, format: .currency(code: "USD").precision(.fractionLength(0))) }
                        }
                    }
                }

                Chart(points) { point in
                    LineMark(
                        x: .value("周期", point.displayLabel),
                        y: .value("ROI", point.roi)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    PointMark(
                        x: .value("周期", point.displayLabel),
                        y: .value("ROI", point.roi)
                    )
                    .foregroundStyle(.green)
                    .symbolSize(34)
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing) { value in
                        AxisValueLabel {
                            if let roi = value.as(Double.self) { Text(roi, format: .number.precision(.fractionLength(2))) }
                        }
                    }
                }
                .chartPlotStyle { plot in plot.background(.clear) }
            }
            .frame(height: 300)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(title)消费销售和 ROI 组合图")
        }
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
