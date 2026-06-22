import SwiftUI

// MARK: - Metrics

enum DashboardToolbarMetrics {
    static let itemSpacing: CGFloat = 10
    static let searchFieldWidth: CGFloat = 200
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 7
}

// MARK: - Liquid Glass

/// Figma `LiquidGlass` → `glassEffect(_:in:)`；旧系统回退 `regularMaterial`。
/// 参考：https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
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
    /// 在 padding 之后调用，与搜索框保持同一渲染路径。
    func dashboardToolbarGlassChrome() -> some View {
        modifier(DashboardToolbarGlassChrome())
    }
}

// MARK: - Pop-Up Button Label

/// Figma `WindowPopUpButton`：标题左对齐，双箭头图标右对齐。
private struct DashboardToolbarPopupLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.subheadline)
                .lineLimit(1)

            Spacer(minLength: 10)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Pop-Up Button Chrome

private extension View {
    func dashboardPopupMenuChrome() -> some View {
        menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .padding(.horizontal, DashboardToolbarMetrics.horizontalPadding)
            .padding(.vertical, DashboardToolbarMetrics.verticalPadding)
            .dashboardToolbarGlassChrome()
            .controlSize(.large)
            .fixedSize()
    }
}

// MARK: - Pop-Up Button

/// Figma `WindowPopUpButton` → `Menu` + `Picker(.inline)`。
/// 玻璃材质加在 `Menu` 外层，与 `DashboardSearchField` 使用相同 API 路径。
struct DashboardToolbarPopupPicker<Option: Hashable>: View {
    let title: String
    @Binding var selection: Option
    let options: [Option]
    let optionTitle: (Option) -> String

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(optionTitle(option)).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            DashboardToolbarPopupLabel(title: title)
        }
        .dashboardPopupMenuChrome()
    }
}

/// 二级 / 三级类目合并筛选。
struct DashboardToolbarCategoryFilter: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        Menu {
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
        } label: {
            DashboardToolbarPopupLabel(title: "二级类目 / 三级类目筛选")
        }
        .dashboardPopupMenuChrome()
    }
}

// MARK: - Search

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

// MARK: - Footer Controls

extension View {
    /// 底部操作按钮：与 Toolbar 控件共用玻璃胶囊样式。
    func dashboardFooterGlassChrome() -> some View {
        padding(.horizontal, DashboardToolbarMetrics.horizontalPadding)
            .padding(.vertical, DashboardToolbarMetrics.verticalPadding)
            .dashboardToolbarGlassChrome()
    }
}
