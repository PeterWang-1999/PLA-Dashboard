import SwiftUI

enum AppSettings {
    @AppStorage("dashboard.defaultPageSize") static var defaultPageSize = 30
    @AppStorage("dashboard.sidebarVisible") static var sidebarVisible = true
}
