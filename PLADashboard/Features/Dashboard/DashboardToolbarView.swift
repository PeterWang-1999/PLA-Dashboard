import SwiftUI

struct DashboardToolbarContent: ToolbarContent {
    @Bindable var viewModel: DashboardViewModel

    var body: some ToolbarContent {
        IndependentToolbarItem(id: "alert-filter", placement: .primaryAction) {
            DashboardToolbarPopupPicker(
                title: "预警筛选",
                selection: $viewModel.selectedAlertFilter,
                options: DashboardViewModel.alertFilterOptions,
                optionTitle: { $0 }
            )
        }
        IndependentToolbarItem(id: "custom-label-filter", placement: .primaryAction) {
            DashboardToolbarPopupPicker(
                title: "自定义标签筛选",
                selection: $viewModel.selectedCustomLabel,
                options: DashboardViewModel.customLabelOptions,
                optionTitle: { $0 }
            )
        }
        IndependentToolbarItem(id: "category-filter", placement: .primaryAction) {
            DashboardToolbarCategoryFilter(viewModel: viewModel)
        }
        IndependentToolbarItem(id: "search", placement: .primaryAction) {
            DashboardSearchField(text: $viewModel.searchText)
        }
    }
}

/// 每个 Toolbar 控件独立成组，避免 macOS 将多个控件包进同一块玻璃背景。
private struct IndependentToolbarItem<Content: View>: ToolbarContent {
    let id: String
    let placement: ToolbarItemPlacement
    @ViewBuilder let content: () -> Content

    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(id: id, placement: placement) {
                content()
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(id: id, placement: placement) {
                content()
            }
        }
    }
}
