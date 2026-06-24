import SwiftUI

@main
struct PLADashboardApp: App {
    @State private var launchState = AppLaunchState.loading

    var body: some Scene {
        WindowGroup {
            Group {
                switch launchState {
                case .loading:
                    ProgressView("正在初始化数据库…")
                        .task {
                            await initializeDatabase()
                        }
                case .ready(let client):
                    RootView()
                        .environment(\.databaseClient, client)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("无法打开数据库", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("重试") {
                            launchState = .loading
                            Task {
                                await initializeDatabase()
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
        }
        .defaultSize(width: 1033, height: 620)
        .windowResizability(.contentMinSize)
    }

    @MainActor
    private func initializeDatabase() async {
        do {
            let client = try DatabaseClient.make()
            try await client.migrateIfNeeded()
            launchState = .ready(client)
        } catch {
            launchState = .failed(error.localizedDescription)
        }
    }
}

private enum AppLaunchState: Equatable {
    case loading
    case ready(DatabaseClient)
    case failed(String)

    static func == (lhs: AppLaunchState, rhs: AppLaunchState) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading):
            true
        case (.ready(let l), .ready(let r)):
            l === r
        case (.failed(let l), .failed(let r)):
            l == r
        default:
            false
        }
    }
}
