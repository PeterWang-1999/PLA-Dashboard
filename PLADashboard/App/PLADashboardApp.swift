import SwiftUI

@main
struct PLADashboardApp: App {
    @State private var accountStore = AccountStore()
    @State private var dashboardSettingsNotifier = DashboardSettingsNotifier()

    var body: some Scene {
        WindowGroup {
            Group {
                switch accountStore.phase {
                case .loading:
                    ProgressView("正在初始化数据库…")
                        .task {
                            await accountStore.bootstrap()
                        }
                case .ready:
                    RootView()
                        .environment(accountStore)
                        .environment(dashboardSettingsNotifier)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("无法打开数据库", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("重试") {
                            Task {
                                await accountStore.bootstrap()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .commands {
            AppCommands()
        }
        Settings {
            SettingsView()
                .environment(accountStore)
                .environment(dashboardSettingsNotifier)
        }
        .defaultSize(width: 1033, height: 620)
        .windowResizability(.contentMinSize)
    }
}
