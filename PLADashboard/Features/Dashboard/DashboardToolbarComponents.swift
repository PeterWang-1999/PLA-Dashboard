import SwiftUI

enum DashboardToolbarMetrics {
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 7
}

// MARK: - Toolbar filter label (align with searchable field)

/// 默认选项使用 secondary；选中具体筛选项时使用 primary。
/// 样式加在 `Menu` 的 `label` 文本上。
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
    /// macOS Pull-down Button — 官方 `Menu` + `borderedButton` 样式。
    func dashboardToolbarPullDownMenuChrome(usesPrimaryStyle: Bool) -> some View {
        menuStyle(.borderedButton)
            .tint(usesPrimaryStyle ? .primary : .secondary)
    }
}

// MARK: - Liquid Glass (footer controls)

struct DashboardToolbarGlassChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

extension View {
    func dashboardToolbarGlassChrome() -> some View {
        modifier(DashboardToolbarGlassChrome())
    }

    func dashboardFooterGlassChrome() -> some View {
        padding(.horizontal, DashboardToolbarMetrics.horizontalPadding)
            .padding(.vertical, DashboardToolbarMetrics.verticalPadding)
            .dashboardToolbarGlassChrome()
    }
}

// MARK: - Pull-down filters (Menu + borderedButton)

struct DashboardToolbarAlertFilterPicker: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        Menu {
            Button(DashboardViewModel.alertFilterDefaultOption) {
                viewModel.selectedAlertFilter = DashboardViewModel.alertFilterDefaultOption
            }

            Divider()

            ForEach(DashboardViewModel.alertFilterOptions.dropFirst(), id: \.self) { value in
                Button(value) {
                    viewModel.selectedAlertFilter = value
                }
            }
        } label: {
            DashboardToolbarFilterLabel(
                title: viewModel.selectedAlertFilter,
                usesPrimaryStyle: viewModel.isAlertFilterActive
            )
        }
        .dashboardToolbarPullDownMenuChrome(usesPrimaryStyle: viewModel.isAlertFilterActive)
    }
}

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
        .dashboardToolbarPullDownMenuChrome(usesPrimaryStyle: viewModel.isCustomLabelFilterActive)
    }
}

// MARK: - Category Menu (nested submenus, single binding)

struct DashboardToolbarCategoryFilter: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        Menu {
            Button(CategoryFilterSelection.defaultTitle) {
                viewModel.selectedCategoryFilter = .all
            }

            Divider()

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
        .dashboardToolbarPullDownMenuChrome(usesPrimaryStyle: viewModel.isCategoryFilterActive)
    }
}
