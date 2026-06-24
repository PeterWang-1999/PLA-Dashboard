import Foundation

enum AppNavigationItem: String, CaseIterable, Identifiable {
    case dashboard = "产品数据"
    case imports = "数据导入"
    case settings = "设置"

    var id: String { rawValue }

    /// 侧边栏可见的导航项（设置通过系统 Settings 窗口打开）。
    static var sidebarCases: [AppNavigationItem] {
        [.dashboard, .imports]
    }

    var systemImage: String {
        switch self {
        case .dashboard: "chart.bar.doc.horizontal"
        case .imports: "square.and.arrow.down"
        case .settings: "gearshape"
        }
    }
}
