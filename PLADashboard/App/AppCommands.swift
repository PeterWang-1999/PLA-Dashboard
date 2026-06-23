import SwiftUI

struct AppCommands: Commands {
    @FocusedValue(\.windowState) private var windowState
    @FocusedValue(\.triggerImportPicker) private var triggerImportPicker
    @FocusedValue(\.refreshDashboardAggregation) private var refreshDashboardAggregation

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
}
