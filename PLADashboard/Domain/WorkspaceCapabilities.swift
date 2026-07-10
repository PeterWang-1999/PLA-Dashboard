import Foundation

struct WorkspaceCapabilities: Equatable, Sendable {
    var importSourceKinds: [ImportSourceKind]
    var sidebarNavigationItems: [AppNavigationItem]

    static func forKind(_ kind: WorkspaceAccountKind) -> WorkspaceCapabilities {
        switch kind {
        case .thirdParty:
            WorkspaceCapabilities(
                importSourceKinds: [.merchantCenter, .adsProduct],
                sidebarNavigationItems: AppNavigationItem.defaultSidebarCases
            )
        case .selfBuilt:
            WorkspaceCapabilities(
                importSourceKinds: [.merchantCenter, .plaDeliveryDetail, .salesReport],
                sidebarNavigationItems: AppNavigationItem.defaultSidebarCases
            )
        }
    }
}
