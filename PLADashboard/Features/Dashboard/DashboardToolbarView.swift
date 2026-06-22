import SwiftUI

struct DashboardToolbarContent: ToolbarContent {
    @Bindable var viewModel: DashboardViewModel

    var body: some ToolbarContent {
        IndependentToolbarItem(id: "alert-filter", placement: .primaryAction) {
            alertFilterButton
        }
        IndependentToolbarItem(id: "custom-label-filter", placement: .primaryAction) {
            customLabelFilterButton
        }
        IndependentToolbarItem(id: "category-filter", placement: .primaryAction) {
            categoryFilterButton
        }
        IndependentToolbarItem(id: "search", placement: .primaryAction) {
            DashboardSearchField(text: $viewModel.searchText)
        }
    }

    private var alertFilterButton: some View {
        DashboardPopupButton(title: "预警筛选") {
            Picker("预警筛选", selection: $viewModel.selectedAlertFilter) {
                ForEach(DashboardViewModel.alertFilterOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.inline)
        }
    }

    private var customLabelFilterButton: some View {
        DashboardPopupButton(title: "自定义标签筛选") {
            Picker("自定义标签筛选", selection: $viewModel.selectedCustomLabel) {
                ForEach(DashboardViewModel.customLabelOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.inline)
        }
    }

    private var categoryFilterButton: some View {
        DashboardPopupButton(title: "二级类目 / 三级类目筛选") {
            Section("二级类目") {
                Picker("二级类目", selection: $viewModel.selectedCategory2) {
                    ForEach(DashboardViewModel.category2Options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.inline)
            }

            Section("三级类目") {
                Picker("三级类目", selection: $viewModel.selectedCategory3) {
                    ForEach(DashboardViewModel.category3Options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.inline)
            }
        }
    }
}

/// 每个 Toolbar 控件独立成组，避免 macOS 将多个控件包进同一块玻璃/胶囊背景。
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
