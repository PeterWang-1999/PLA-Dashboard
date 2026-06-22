import SwiftUI

// MARK: - Search

enum DashboardToolbarMetrics {
    static let searchFieldWidth: CGFloat = 200
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 7
}

/// Figma `WindowSearch` → `TextField` + `glassEffect`。
struct DashboardSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("输入 LSIN 查询", text: $text)
                .textFieldStyle(.plain)
                .font(.subheadline)
        }
        .padding(.horizontal, DashboardToolbarMetrics.horizontalPadding)
        .padding(.vertical, DashboardToolbarMetrics.verticalPadding)
        .frame(width: DashboardToolbarMetrics.searchFieldWidth)
        .dashboardToolbarGlassChrome()
        .fixedSize()
    }
}

// MARK: - Liquid Glass (search field)

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
            Text(DashboardViewModel.alertFilterPlaceholder)
                .tag(DashboardViewModel.alertFilterPlaceholder)
            ForEach(DashboardViewModel.alertFilterValues, id: \.self) { value in
                Text(value).tag(value)
            }
        }
        .pickerStyle(.menu)
    }
}

struct DashboardToolbarCustomLabelFilterPicker: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        Picker("自定义标签筛选", selection: $viewModel.selectedCustomLabel) {
            Text(DashboardViewModel.customLabelPlaceholder)
                .tag(DashboardViewModel.customLabelPlaceholder)
            ForEach(DashboardViewModel.customLabelValues, id: \.self) { value in
                Text(value).tag(value)
            }
        }
        .pickerStyle(.menu)
    }
}

// MARK: - Category Menu (Pull-down + nested submenus, single binding)

struct DashboardToolbarCategoryFilter: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        Menu {
            Button(CategoryFilterSelection.placeholderTitle) {
                viewModel.selectedCategoryFilter = .none
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
    }
}
