import Foundation
import Observation

/// 看板相关设置在 Settings 窗口变更时递增 revision，供主窗口通过 Observation 刷新。
@MainActor
@Observable
final class DashboardSettingsNotifier {
    private(set) var revision: UInt = 0

    func notifyChange() {
        revision &+= 1
    }
}
