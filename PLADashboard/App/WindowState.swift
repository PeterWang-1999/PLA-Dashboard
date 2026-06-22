import SwiftUI

@Observable
final class WindowState {
    var isSidebarVisible: Bool
    var columnVisibility: NavigationSplitViewVisibility

    init(isSidebarVisible: Bool = true) {
        self.isSidebarVisible = isSidebarVisible
        self.columnVisibility = isSidebarVisible ? .all : .detailOnly
    }

    func toggleSidebar() {
        isSidebarVisible.toggle()
        columnVisibility = isSidebarVisible ? .all : .detailOnly
    }

    func syncFromSceneStorage(_ stored: Bool) {
        isSidebarVisible = stored
        columnVisibility = stored ? .all : .detailOnly
    }
}
