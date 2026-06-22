import SwiftUI

/// macOS Window/Pop-Up Button（Figma: WindowPopUpButton, size XL）
struct DashboardPopupButton<MenuContent: View>: View {
    let title: String
    @ViewBuilder let menuContent: () -> MenuContent

    var body: some View {
        Menu {
            menuContent()
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(DashboardToolbarMetrics.controlBackground, in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .fixedSize()
    }
}

/// macOS Window/Search（Figma: WindowSearch, size XL）
struct DashboardSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            TextField("输入 LSIN 查询", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(width: DashboardToolbarMetrics.searchFieldWidth)
        .background(DashboardToolbarMetrics.controlBackground, in: Capsule())
        .contentShape(Capsule())
        .fixedSize()
    }
}

enum DashboardToolbarMetrics {
    static let itemSpacing: CGFloat = 10
    static let searchFieldWidth: CGFloat = 200

    static var controlBackground: some ShapeStyle {
        Color(.quaternarySystemFill)
    }
}
