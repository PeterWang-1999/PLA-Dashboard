import SwiftUI

/// 当前产品数据上下文中的账户级维护操作。
struct DashboardMaintenanceMenu: View {
    @Environment(AccountStore.self) private var accountStore
    @Environment(DashboardSettingsNotifier.self) private var dashboardSettingsNotifier
    @Environment(BIDownloadStore.self) private var downloads

    @State private var showPurgeConfirmation = false
    @State private var pendingPurgeCount = 0
    @State private var isPurging = false
    @State private var purgeResultMessage: String?
    @State private var showPurgeResult = false
    @State private var isRunningProductDiagnostics = false
    @State private var productDiagnosticsMessage: String?
    @State private var showProductDiagnosticsResult = false
    @State private var showReconcileConfirmation = false

    var body: some View {
        Menu {
            if accountStore.activeAccount?.kind == .selfBuilt {
                Button {
                    Task { await downloads.synchronizeProductData(accountStore: accountStore) }
                } label: {
                    Label("同步数据", systemImage: "arrow.clockwise")
                }
                .disabled(accountStore.isImportInProgress || isPurging || isRunningProductDiagnostics)
            }

            Section("数据保留") {
                Button("清理过期 Ads 数据…", role: .destructive) {
                    Task { await preparePurgeConfirmation() }
                }
                .disabled(retentionDays == 0 || isPurging || accountStore.isImportInProgress)
            }

            Section("产品图") {
                Button("诊断产品图数据…") {
                    Task { await runProductDiagnostics() }
                }
                .disabled(isRunningProductDiagnostics)

                Button("合并 S 前缀产品记录…") {
                    showReconcileConfirmation = true
                }
                .disabled(isRunningProductDiagnostics || accountStore.isImportInProgress)
            }
        } label: {
            if let progress = downloads.syncProgress {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(progress)
                }
            } else {
                Label("数据维护", systemImage: "wrench.and.screwdriver")
            }
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
            "确认合并 S 前缀产品记录？",
            isPresented: $showReconcileConfirmation,
            titleVisibility: .visible
        ) {
            Button("合并记录") {
                Task { await reconcilePrefixedProducts() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将在当前账户中合并带 S 前缀与不带前缀的同一产品记录，并刷新看板数据。")
        }
        .alert("数据清理", isPresented: $showPurgeResult) {
            Button("好", role: .cancel) {}
        } message: {
            Text(purgeResultMessage ?? "")
        }
        .alert("产品图诊断", isPresented: $showProductDiagnosticsResult) {
            Button("好", role: .cancel) {}
        } message: {
            Text(productDiagnosticsMessage ?? "")
        }
        .alert("同步数据", isPresented: Binding(
            get: { downloads.syncResult != nil },
            set: { if !$0 { downloads.syncResult = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(downloads.syncResult ?? "")
        }
    }

    private var accountID: String? {
        accountStore.activeAccountID
    }

    private var accountName: String {
        accountStore.activeAccount?.name ?? accountID ?? "当前账户"
    }

    private var retentionDays: Int {
        guard let accountID else { return 0 }
        return AppSettings.dataRetentionDays(accountID: accountID)
    }

    private var maintenanceHelp: String {
        retentionDays == 0
            ? "可在设置中启用数据保留期限；此处执行账户数据维护"
            : "清理当前账户的过期数据"
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
        guard !accountStore.isImportInProgress else { return }
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
    private func runProductDiagnostics() async {
        guard let client = activeDatabaseClient else {
            showProductDiagnosticsFailure("数据库未就绪")
            return
        }
        isRunningProductDiagnostics = true
        defer { isRunningProductDiagnostics = false }
        do {
            let report = try await client.buildProductImageDiagnosticsReport(accountName: accountName)
            productDiagnosticsMessage = report.formattedText
            showProductDiagnosticsResult = true
        } catch {
            showProductDiagnosticsFailure(error.localizedDescription)
        }
    }

    @MainActor
    private func reconcilePrefixedProducts() async {
        guard !accountStore.isImportInProgress else { return }
        guard let client = activeDatabaseClient else {
            showProductDiagnosticsFailure("数据库未就绪")
            return
        }
        isRunningProductDiagnostics = true
        defer { isRunningProductDiagnostics = false }
        do {
            try await client.reconcileLsinPrefixedProductIDs()
            let report = try await client.buildProductImageDiagnosticsReport(accountName: accountName)
            productDiagnosticsMessage = "已合并 S 前缀产品记录。\n\n\(report.formattedText)"
            showProductDiagnosticsResult = true
            dashboardSettingsNotifier.notifyChange()
        } catch {
            showProductDiagnosticsFailure(error.localizedDescription)
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

    private func showProductDiagnosticsFailure(_ message: String) {
        productDiagnosticsMessage = message
        showProductDiagnosticsResult = true
    }
}
