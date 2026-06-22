import SwiftUI

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel
    @Bindable var windowState: WindowState

    var body: some View {
        VStack(spacing: 0) {
            DashboardToolbarView(viewModel: viewModel)

            Divider()

            ZStack {
                if viewModel.isEmpty {
                    DashboardEmptyStateView()
                } else {
                    ProductPerformanceTable(
                        rows: viewModel.rows,
                        visibleColumns: DashboardColumnLayout.visibleColumns(
                            isSidebarVisible: windowState.isSidebarVisible
                        )
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            dashboardFooter
        }
        .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: "搜索 LSIN / 标签")
        .navigationTitle("产品数据")
        .navigationSubtitle(viewModel.selectedTimeDimension)
    }

    private var dashboardFooter: some View {
        HStack {
            Spacer()

            Button("数据更新") {
                viewModel.refreshData()
            }
            .buttonStyle(.bordered)

            Menu("快捷操作") {
                Button("导出当前视图") {}
                Button("刷新聚合") {}
            }
            .menuStyle(.borderlessButton)

            HStack(spacing: 4) {
                Button {
                    viewModel.goToPreviousPage()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(viewModel.currentPage <= 1)

                Text("第 \(viewModel.currentPage) / \(viewModel.totalPages) 页")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 100)

                Button {
                    viewModel.goToNextPage()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(viewModel.currentPage >= viewModel.totalPages)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 44)
    }
}

#Preview("Sidebar Expanded") {
    DashboardView(
        viewModel: DashboardViewModel(),
        windowState: WindowState(isSidebarVisible: true)
    )
    .frame(width: 783, height: 620)
}

#Preview("Sidebar Collapsed") {
    let state = WindowState(isSidebarVisible: false)
    return DashboardView(
        viewModel: DashboardViewModel(),
        windowState: state
    )
    .frame(width: 1033, height: 620)
}
