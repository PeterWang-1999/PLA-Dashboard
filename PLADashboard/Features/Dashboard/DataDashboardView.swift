import SwiftUI

/// 趋势图时间粒度：周 / 日。
private enum TrendGranularity: String, CaseIterable {
    case weekly = "周维度"
    case daily = "日维度"
}

struct DataDashboardView: View {
    @Bindable var viewModel: DashboardViewModel
    let accountKind: WorkspaceAccountKind
    var onRequestDataUpdate: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var trendGranularity: TrendGranularity = .weekly
    @State private var trendProgress: Double = 0
    /// 工具栏筛选变化时驱动「旧 → 新」弹性过渡的进度（0 = 旧数据，1 = 新数据）。
    @State private var filterProgress: Double = 1
    /// 筛选前捕获的旧趋势，作为插值起点。
    @State private var fromWeekly: [DataDashboardTrendPoint] = []
    @State private var fromDaily: [DataDashboardTrendPoint] = []

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
        .onChange(of: viewModel.isLoadingDataDashboard) { _, isLoading in
            if isLoading {
                // 刷新开始：把当前已展示的数据冻结为插值起点，避免新数据到达时瞬时跳变。
                fromWeekly = snapshot.weeklyTrend
                fromDaily = snapshot.dailyTrend
                filterProgress = 0
            } else {
                // 刷新完成：从旧数据弹性过渡到新快照；首次加载无基线则直接呈现。
                guard !fromWeekly.isEmpty || !fromDaily.isEmpty else {
                    filterProgress = 1
                    return
                }
                let animation: Animation = reduceMotion
                    ? .easeInOut(duration: 0.2)
                    : .spring(response: 0.45, dampingFraction: 0.82)
                withAnimation(animation) {
                    filterProgress = 1
                }
            }
        }
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
                    .background(
                        reduceTransparency
                            ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
                            : AnyShapeStyle(.regularMaterial),
                        in: Capsule()
                    )
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
            FilterMorphingTrendChart(
                fromWeekly: fromWeekly,
                fromDaily: fromDaily,
                toWeekly: snapshot.weeklyTrend,
                toDaily: snapshot.dailyTrend,
                granularityProgress: trendProgress,
                filterProgress: filterProgress
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
