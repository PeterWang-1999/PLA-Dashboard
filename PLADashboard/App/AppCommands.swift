import SwiftUI

struct AppCommands: Commands {
    @FocusedValue(\.triggerImportPicker) private var triggerImportPicker
    @FocusedValue(\.refreshDashboardAggregation) private var refreshDashboardAggregation
    @FocusedValue(\.dashboardGoToPreviousPage) private var dashboardGoToPreviousPage
    @FocusedValue(\.dashboardGoToNextPage) private var dashboardGoToNextPage
    @FocusedValue(\.dashboardGoToFirstPage) private var dashboardGoToFirstPage
    @FocusedValue(\.dashboardGoToLastPage) private var dashboardGoToLastPage
    @FocusedValue(\.openSelectedProductDetail) private var openSelectedProductDetail

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
            Button("查看产品明细") {
                openSelectedProductDetail?()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(openSelectedProductDetail == nil)

            Divider()

            Button("首页") {
                dashboardGoToFirstPage?()
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(dashboardGoToFirstPage == nil)

            Button("上一页") {
                dashboardGoToPreviousPage?()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(dashboardGoToPreviousPage == nil)

            Button("下一页") {
                dashboardGoToNextPage?()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(dashboardGoToNextPage == nil)

            Button("尾页") {
                dashboardGoToLastPage?()
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(dashboardGoToLastPage == nil)
        }
    }
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

private struct DashboardGoToFirstPageFocusedKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct DashboardGoToLastPageFocusedKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct OpenSelectedProductDetailFocusedKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
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

    var dashboardGoToFirstPage: (() -> Void)? {
        get { self[DashboardGoToFirstPageFocusedKey.self] }
        set { self[DashboardGoToFirstPageFocusedKey.self] = newValue }
    }

    var dashboardGoToLastPage: (() -> Void)? {
        get { self[DashboardGoToLastPageFocusedKey.self] }
        set { self[DashboardGoToLastPageFocusedKey.self] = newValue }
    }


    var openSelectedProductDetail: (() -> Void)? {
        get { self[OpenSelectedProductDetailFocusedKey.self] }
        set { self[OpenSelectedProductDetailFocusedKey.self] = newValue }
    }
}
