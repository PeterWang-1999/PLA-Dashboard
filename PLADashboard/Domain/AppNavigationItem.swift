import Foundation

enum AppNavigationItem: String, CaseIterable, Identifiable {
    case dashboard = "产品数据"
    case dataDashboard = "数据看板"
    case imports = "数据导入"

    var id: String { rawValue }

    /// 侧边栏可见的导航项（设置通过系统 Settings 窗口打开）。
    static var defaultSidebarCases: [AppNavigationItem] {
        [.dashboard, .dataDashboard, .imports]
    }

    static func sidebarCases(for kind: WorkspaceAccountKind) -> [AppNavigationItem] {
        WorkspaceCapabilities.forKind(kind).sidebarNavigationItems
    }

    var systemImage: String {
        switch self {
        case .dashboard: "chart.bar.doc.horizontal"
        case .dataDashboard: "chart.xyaxis.line"
        case .imports: "square.and.arrow.down"
        }
    }
}
