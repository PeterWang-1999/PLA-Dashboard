import SwiftUI

// MARK: - Toolbar filter label (align with searchable field)

/// 默认选项使用 secondary；选中具体筛选项时使用 primary。
private struct DashboardToolbarFilterLabel: View {
    let title: String
    let usesPrimaryStyle: Bool

    var body: some View {
        Text(title)
            .font(.body)
            .foregroundStyle(usesPrimaryStyle ? .primary : .secondary)
    }
}

private extension View {
    /// macOS Pull-down — 官方 `Menu` + `borderedButton`。
    func dashboardToolbarPullDownMenuChrome() -> some View {
        menuStyle(.borderedButton)
    }
}

// MARK: - Pull-down filters (Menu + borderedButton)

struct DashboardToolbarCustomLabelFilterPicker: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        Menu {
            Button(CustomLabelFilterSelection.defaultTitle) {
                viewModel.selectedCustomLabelFilter = .all
            }

            Divider()

            ForEach(viewModel.customLabelCatalog.groups) { group in
                if group.hasValueChildren {
                    Menu(group.columnName) {
                        Button("全部 \(group.columnName)") {
                            viewModel.selectedCustomLabelFilter = .column(group.columnName)
                        }

                        Divider()

                        ForEach(group.values, id: \.self) { value in
                            Button(value) {
                                viewModel.selectedCustomLabelFilter = .value(
                                    column: group.columnName,
                                    value: value
                                )
                            }
                        }
                    }
                } else {
                    Button(group.columnName) {
                        viewModel.selectedCustomLabelFilter = .column(group.columnName)
                    }
                }
            }
        } label: {
            DashboardToolbarFilterLabel(
                title: viewModel.selectedCustomLabelFilter.menuTitle,
                usesPrimaryStyle: viewModel.isCustomLabelFilterActive
            )
        }
        .dashboardToolbarPullDownMenuChrome()
        .accessibilityLabel("自定义标签筛选")
        .accessibilityValue(viewModel.selectedCustomLabelFilter.menuTitle)
        .modifier(DashboardToolbarFilterEmptyHelp(message: viewModel.customLabelFilterEmptyHelp))
    }
}

struct DashboardToolbarProductTagFilter: View {
    @Bindable var viewModel: DashboardViewModel

    private let allTags = "全部效果标签"

    var body: some View {
        Menu {
            Picker("效果标签", selection: $viewModel.selectedProductTag) {
                Text(allTags).tag(nil as String?)
                ForEach(viewModel.productTags, id: \.self) { tag in
                    Text(tag).tag(tag as String?)
                }
            }
            .pickerStyle(.inline)
        } label: {
            DashboardToolbarFilterLabel(
                title: viewModel.selectedProductTag ?? allTags,
                usesPrimaryStyle: viewModel.selectedProductTag != nil
            )
        }
        .dashboardToolbarPullDownMenuChrome()
        .accessibilityLabel("效果标签筛选")
        .accessibilityValue(viewModel.selectedProductTag ?? allTags)
        .modifier(DashboardToolbarFilterEmptyHelp(
            message: viewModel.productTags.isEmpty ? "同步投放产品明细后，这里会显示可选的效果标签" : nil
        ))
    }
}

struct DashboardToolbarCategoryFilter: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        Menu {
            Button(CategoryFilterSelection.defaultTitle) {
                viewModel.selectedCategoryFilter = .all
            }

            Divider()

            ForEach(viewModel.plaCategories) { category in
                PlaCategoryMenuItem(category: category, selection: $viewModel.selectedCategoryFilter)
            }
            ForEach(viewModel.categoryCatalog.groups) { group in
                if group.hasLevel3Children {
                    Menu(group.level2) {
                        Button("全部 \(group.level2)") {
                            viewModel.selectedCategoryFilter = .level2(group.level2)
                        }

                        Divider()

                        ForEach(group.level3, id: \.self) { level3 in
                            Button(level3) {
                                viewModel.selectedCategoryFilter = .level3(
                                    level2: group.level2,
                                    level3: level3
                                )
                            }
                        }
                    }
                } else {
                    Button(group.level2) {
                        viewModel.selectedCategoryFilter = .level2(group.level2)
                    }
                }
            }
        } label: {
            DashboardToolbarFilterLabel(
                title: viewModel.selectedCategoryFilter.menuTitle,
                usesPrimaryStyle: viewModel.isCategoryFilterActive
            )
        }
        .dashboardToolbarPullDownMenuChrome()
        .accessibilityLabel("类目筛选")
        .accessibilityValue(viewModel.selectedCategoryFilter.menuTitle)
        .modifier(DashboardToolbarFilterEmptyHelp(message: viewModel.categoryFilterEmptyHelp))
    }
}

private struct PlaCategoryMenuItem: View {
    let category: PlaCategoryNode
    @Binding var selection: CategoryFilterSelection

    var body: some View {
        if category.children.isEmpty {
            Button(category.name) { selection = .plaPath(category.path) }
        } else {
            Menu(category.name) {
                Button("全部 \(category.name)") { selection = .plaPath(category.path) }
                Divider()
                ForEach(category.children) { child in
                    PlaCategoryMenuItem(category: child, selection: $selection)
                }
            }
        }
    }
}

private struct DashboardToolbarFilterEmptyHelp: ViewModifier {
    let message: String?

    func body(content: Content) -> some View {
        if let message {
            content.help(message)
        } else {
            content
        }
    }
}
