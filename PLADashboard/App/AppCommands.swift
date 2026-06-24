import SwiftUI

struct AppCommands: Commands {
    @FocusedValue(\.windowState) private var windowState
    @FocusedValue(\.triggerImportPicker) private var triggerImportPicker
    @FocusedValue(\.refreshDashboardAggregation) private var refreshDashboardAggregation
    @FocusedValue(\.dashboardGoToPreviousPage) private var dashboardGoToPreviousPage
    @FocusedValue(\.dashboardGoToNextPage) private var dashboardGoToNextPage

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("导入数据…") {
                triggerImportPicker?()
            }
            .keyboardShortcut("I", modifiers: [.command, .shift])

            Button("刷新聚合") {
                refreshDashboardAggregation?()
            }
            .keyboardShortcut("R", modifiers: [.command, .shift])
        }

        CommandMenu("看板") {
            Button("上一页") {
                dashboardGoToPreviousPage?()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Button("下一页") {
                dashboardGoToNextPage?()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
        }

        CommandGroup(after: .sidebar) {
            Button("切换侧边栏") {
                windowState?.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
        }
    }
}

private struct WindowStateFocusedKey: FocusedValueKey {
    typealias Value = WindowState
}

private struct TriggerImportPickerFocusedKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct RefreshDashboardAggregationFocusedKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct DashboardGoToPreviousPageFocusedKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct DashboardGoToNextPageFocusedKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var windowState: WindowState? {
        get { self[WindowStateFocusedKey.self] }
        set { self[WindowStateFocusedKey.self] = newValue }
    }

    var triggerImportPicker: (() -> Void)? {
        get { self[TriggerImportPickerFocusedKey.self] }
        set { self[TriggerImportPickerFocusedKey.self] = newValue }
    }

    var refreshDashboardAggregation: (() -> Void)? {
        get { self[RefreshDashboardAggregationFocusedKey.self] }
        set { self[RefreshDashboardAggregationFocusedKey.self] = newValue }
    }

    var dashboardGoToPreviousPage: (() -> Void)? {
        get { self[DashboardGoToPreviousPageFocusedKey.self] }
        set { self[DashboardGoToPreviousPageFocusedKey.self] = newValue }
    }

    var dashboardGoToNextPage: (() -> Void)? {
        get { self[DashboardGoToNextPageFocusedKey.self] }
        set { self[DashboardGoToNextPageFocusedKey.self] = newValue }
    }
}
