import SwiftUI

enum DashboardToolbarMetrics {
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 7
}

// MARK: - Toolbar filter label (align with searchable field)

/// 默认选项使用 secondary；选中具体筛选项时使用 primary。
private struct DashboardToolbarFilterLabelStyle: ViewModifier {
    let usesPrimaryStyle: Bool

    func body(content: Content) -> some View {
        content
            .font(.body)
            .foregroundStyle(usesPrimaryStyle ? .primary : .secondary)
            .tint(usesPrimaryStyle ? .primary : .secondary)
    }
}

private extension View {
    func dashboardToolbarFilterLabelStyle(usesPrimaryStyle: Bool) -> some View {
        modifier(DashboardToolbarFilterLabelStyle(usesPrimaryStyle: usesPrimaryStyle))
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

// MARK: - Pop-Up Button (Picker + .menu)

struct DashboardToolbarAlertFilterPicker: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        Picker("预警筛选", selection: $viewModel.selectedAlertFilter) {
            ForEach(DashboardViewModel.alertFilterOptions, id: \.self) { value in
                Text(value).tag(value)
            }
        }
        .pickerStyle(.menu)
        .dashboardToolbarFilterLabelStyle(usesPrimaryStyle: viewModel.isAlertFilterActive)
    }
}

struct DashboardToolbarCustomLabelFilterPicker: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        Picker("自定义标签筛选", selection: $viewModel.selectedCustomLabel) {
            ForEach(DashboardViewModel.customLabelOptions, id: \.self) { value in
                Text(value).tag(value)
            }
        }
        .pickerStyle(.menu)
        .dashboardToolbarFilterLabelStyle(usesPrimaryStyle: viewModel.isCustomLabelFilterActive)
    }
}

// MARK: - Category Menu (Pull-down + nested submenus, single binding)

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
            Text(viewModel.selectedCategoryFilter.menuTitle)
        }
        .dashboardToolbarFilterLabelStyle(usesPrimaryStyle: viewModel.isCategoryFilterActive)
    }
}
