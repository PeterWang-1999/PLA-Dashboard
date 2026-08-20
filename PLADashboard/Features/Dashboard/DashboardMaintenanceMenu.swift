import SwiftUI

/// 当前产品数据上下文中的账户级维护操作。
struct DashboardMaintenanceMenu: View {
    @Environment(AccountStore.self) private var accountStore
    @Environment(DashboardSettingsNotifier.self) private var dashboardSettingsNotifier

    @State private var showPurgeConfirmation = false
    @State private var pendingPurgeCount = 0
    @State private var isPurging = false
    @State private var purgeResultMessage: String?
    @State private var showPurgeResult = false
    @State private var showResetLabelsConfirmation = false
    @State private var isUpdatingLabels = false
    @State private var labelsResultMessage: String?
    @State private var showLabelsResult = false

    var body: some View {
        Menu {
            if isSelfBuiltAccount {
                Section("预警标签") {
                    Button("重新计算预警标签") {
                        Task { await performRefreshLabels() }
                    }
                    .disabled(isUpdatingLabels)

                    Button("重置预警标签历史…", role: .destructive) {
                        showResetLabelsConfirmation = true
                    }
                    .disabled(isUpdatingLabels)
                }
            }

            Section("数据保留") {
                Button("清理过期 Ads 数据…", role: .destructive) {
                    Task { await preparePurgeConfirmation() }
                }
                .disabled(retentionDays == 0 || isPurging)
            }
        } label: {
            Label("数据维护", systemImage: "wrench.and.screwdriver")
        }
        .menuStyle(.borderedButton)
        .controlSize(.large)
        .help(maintenanceHelp)
        .confirmationDialog(
            "确认清理过期数据？",
            isPresented: $showPurgeConfirmation,
            titleVisibility: .visible
        ) {
            Button("清理 \(pendingPurgeCount) 行", role: .destructive) {
                Task { await performPurge() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除当前账户 \(pendingPurgeCount) 行 ads_product_daily 记录（早于保留 \(retentionDays) 天）。产品主表与导入记录保留。")
        }
        .confirmationDialog(
            "确认重置预警标签历史？",
            isPresented: $showResetLabelsConfirmation,
            titleVisibility: .visible
        ) {
            Button("重置并重新入池", role: .destructive) {
                Task { await performResetLabels() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除当前账户全部标签周快照，并按当前完整报告周仅执行入池规则。留池/出池的“连续 2 次”计数将从零开始。")
        }
        .alert("数据清理", isPresented: $showPurgeResult) {
            Button("好", role: .cancel) {}
        } message: {
            Text(purgeResultMessage ?? "")
        }
        .alert("预警标签", isPresented: $showLabelsResult) {
            Button("好", role: .cancel) {}
        } message: {
            Text(labelsResultMessage ?? "")
        }
    }

    private var accountID: String? {
        accountStore.activeAccountID
    }

    private var isSelfBuiltAccount: Bool {
        accountStore.activeAccount?.kind == .selfBuilt
    }

    private var retentionDays: Int {
        guard let accountID else { return 0 }
        return AppSettings.dataRetentionDays(accountID: accountID)
    }

    private var maintenanceHelp: String {
        retentionDays == 0
            ? "可在设置中启用数据保留期限；此处执行账户数据维护"
            : "重新计算标签或清理当前账户的过期数据"
    }

    @MainActor
    private func preparePurgeConfirmation() async {
        guard retentionDays > 0, let client = activeDatabaseClient else { return }
        isPurging = true
        defer { isPurging = false }
        do {
            pendingPurgeCount = try await client.countExpiredAdsDailyRows(retentionDays: retentionDays)
            if pendingPurgeCount == 0 {
                purgeResultMessage = "没有需要清理的过期数据。"
                showPurgeResult = true
            } else {
                showPurgeConfirmation = true
            }
        } catch {
            purgeResultMessage = error.localizedDescription
            showPurgeResult = true
        }
    }

    @MainActor
    private func performPurge() async {
        guard let client = activeDatabaseClient else {
            showPurgeFailure("数据库未就绪")
            return
        }
        isPurging = true
        defer { isPurging = false }
        do {
            let deleted = try await client.purgeExpiredAdsDaily(retentionDays: retentionDays)
            if let accountID, let latestDay = try await client.fetchLatestMetricDay() {
                AppSettings.setLastRetentionPurgeDay(latestDay, accountID: accountID)
            }
            purgeResultMessage = "已删除 \(deleted) 行过期 Ads 日表数据，并已重建周聚合。"
            showPurgeResult = true
            dashboardSettingsNotifier.notifyChange()
        } catch {
            showPurgeFailure(error.localizedDescription)
        }
    }

    @MainActor
    private func performRefreshLabels() async {
        guard let client = activeDatabaseClient else {
            showLabelsFailure("数据库未就绪")
            return
        }
        isUpdatingLabels = true
        defer { isUpdatingLabels = false }
        do {
            let outcome = try await client.recomputeWarningLabelsIfNeeded(
                force: false,
                refreshSameWeek: true
            )
            switch outcome {
            case .computed(let weekID, let count, let note):
                labelsResultMessage = "已重新计算：报告周 \(weekID)，共 \(count) 个产品。\(note)"
            case .skippedNoAdsData:
                labelsResultMessage = "当前无投放数据，无法计算标签。"
            case .skippedInsufficientWeeks(let available):
                labelsResultMessage = "完整报告周不足（当前 \(available) 周），无法计算标签。"
            case .skippedAlreadyComputed(let weekID):
                labelsResultMessage = "报告周 \(weekID) 已是最新，无需重算。"
            }
            showLabelsResult = true
            dashboardSettingsNotifier.notifyChange()
        } catch {
            showLabelsFailure(error.localizedDescription)
        }
    }

    @MainActor
    private func performResetLabels() async {
        guard let client = activeDatabaseClient else {
            showLabelsFailure("数据库未就绪")
            return
        }
        isUpdatingLabels = true
        defer { isUpdatingLabels = false }
        do {
            let outcome = try await client.recomputeWarningLabelsIfNeeded(force: true)
            switch outcome {
            case .computed(let weekID, let count, _):
                labelsResultMessage = "已重置历史并完成入池：报告周 \(weekID)，共 \(count) 个产品。"
            case .skippedNoAdsData:
                labelsResultMessage = "已清空历史，但当前无投放数据，无法计算标签。"
            case .skippedInsufficientWeeks(let available):
                labelsResultMessage = "已清空历史，但完整报告周不足（当前 \(available) 周），无法计算标签。"
            case .skippedAlreadyComputed:
                labelsResultMessage = "已重置历史。"
            }
            showLabelsResult = true
            dashboardSettingsNotifier.notifyChange()
        } catch {
            showLabelsFailure(error.localizedDescription)
        }
    }

    private var activeDatabaseClient: DatabaseClient? {
        guard let accountID,
              let client = accountStore.activeDatabaseClient,
              client.accountID == accountID else {
            return nil
        }
        return client
    }

    private func showPurgeFailure(_ message: String) {
        purgeResultMessage = message
        showPurgeResult = true
    }

    private func showLabelsFailure(_ message: String) {
        labelsResultMessage = message
        showLabelsResult = true
    }
}
