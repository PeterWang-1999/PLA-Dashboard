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

/// Figma `WindowPopUpButton` 固定标题 + 双箭头（不含背景，背景由外层 `glassEffect` 提供）。
private struct DashboardToolbarPopupLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
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
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .padding(.horizontal, DashboardToolbarMetrics.horizontalPadding)
        .padding(.vertical, DashboardToolbarMetrics.verticalPadding)
        .dashboardToolbarGlassChrome()
        .controlSize(.large)
        .fixedSize()
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
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .padding(.horizontal, DashboardToolbarMetrics.horizontalPadding)
        .padding(.vertical, DashboardToolbarMetrics.verticalPadding)
        .dashboardToolbarGlassChrome()
        .controlSize(.large)
        .fixedSize()
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
