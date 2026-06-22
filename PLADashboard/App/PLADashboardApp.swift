import SwiftUI

@main
struct PLADashboardApp: App {
    @State private var databaseClient: DatabaseClient?

    var body: some Scene {
        WindowGroup {
            Group {
                if let databaseClient {
                    RootView()
                        .environment(\.databaseClient, databaseClient)
                } else {
                    ProgressView("正在初始化数据库…")
                        .task {
                            await initializeDatabase()
                        }
                }
            }
        }
        .commands {
            AppCommands()
        }
        .defaultSize(width: 1033, height: 620)
        .windowResizability(.contentMinSize)
    }

    @MainActor
    private func initializeDatabase() async {
        do {
            let client = try DatabaseClient.make()
            try await client.migrateIfNeeded()
            databaseClient = client
        } catch {
            #if DEBUG
            fatalError("无法初始化 DatabaseClient: \(error)")
            #else
            fatalError("无法初始化 DatabaseClient。")
            #endif
        }
    }
}
