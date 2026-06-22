import SwiftUI

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel
    @Bindable var windowState: WindowState

    var body: some View {
        VStack(spacing: 0) {
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
        .navigationTitle("产品数据")
        .toolbar {
            DashboardToolbarContent(viewModel: viewModel)
        }
    }

    private var dashboardFooter: some View {
        HStack(spacing: 10) {
            Spacer()

            Button("数据更新") {
                viewModel.refreshData()
            }
            .dashboardFooterGlassChrome()
            .buttonStyle(.plain)
            .controlSize(.large)

            Menu {
                Button("导出当前视图") {}
                Button("刷新聚合") {}
            } label: {
                Text("快捷操作")
                    .dashboardFooterGlassChrome()
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .controlSize(.large)

            paginationControls
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 44)
    }

    private var paginationControls: some View {
        HStack(spacing: 4) {
            Button {
                viewModel.goToPreviousPage()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(viewModel.currentPage <= 1)

            Text("第 \(viewModel.currentPage) / \(viewModel.totalPages) 页")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(minWidth: 100)

            Button {
                viewModel.goToNextPage()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(viewModel.currentPage >= viewModel.totalPages)
        }
        .dashboardFooterGlassChrome()
    }
}

#Preview("Sidebar Expanded") {
    NavigationStack {
        DashboardView(
            viewModel: DashboardViewModel(),
            windowState: WindowState(isSidebarVisible: true)
        )
    }
    .frame(width: 783, height: 620)
}

#Preview("Sidebar Collapsed") {
    NavigationStack {
        DashboardView(
            viewModel: DashboardViewModel(),
            windowState: WindowState(isSidebarVisible: false)
        )
    }
    .frame(width: 1033, height: 620)
}
