import Foundation

enum AppNavigationItem: String, CaseIterable, Identifiable {
    case dashboard = "产品数据"
    case imports = "数据导入"
    case settings = "设置"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dashboard: "chart.bar.doc.horizontal"
        case .imports: "square.and.arrow.down"
        case .settings: "gearshape"
        }
    }
}
