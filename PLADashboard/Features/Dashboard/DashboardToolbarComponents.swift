import SwiftUI

// MARK: - Metrics

enum DashboardToolbarMetrics {
    static let itemSpacing: CGFloat = 10
    static let searchFieldWidth: CGFloat = 200
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 7
}

// MARK: - Liquid Glass / Material

/// Figma `LiquidGlass` → macOS 26 `glassEffect`,macOS 14–25 回退 `regularMaterial`。
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
}

/// 交互控件的玻璃按钮样式：macOS 26 用系统 `.glass`，旧版用 Material 胶囊。
struct DashboardGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26.0, *) {
            configuration.label
                .opacity(configuration.isPressed ? 0.88 : 1)
        } else {
            configuration.label
                .dashboardToolbarGlassChrome()
                .opacity(configuration.isPressed ? 0.88 : 1)
        }
    }
}

extension View {
    @ViewBuilder
    func dashboardGlassControl() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
                .controlSize(.large)
        } else {
            buttonStyle(DashboardGlassButtonStyle())
                .controlSize(.large)
        }
    }
}

// MARK: - Window/Pop-Up Button Label

/// Figma `WindowPopUpButton` 固定标题 + 双箭头。
struct DashboardToolbarPopupLabel: View {
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
        .padding(.horizontal, DashboardToolbarMetrics.horizontalPadding)
        .padding(.vertical, DashboardToolbarMetrics.verticalPadding)
    }
}

// MARK: - Window/Pop-Up Button (Menu + Picker)

/// Figma `WindowPopUpButton` → `Menu` + `Picker(.inline)`，保持固定标题。
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
        .dashboardGlassControl()
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
        .dashboardGlassControl()
        .fixedSize()
    }
}

// MARK: - Window/Search

/// Figma `WindowSearch` → `TextField` + 玻璃胶囊背景。
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
