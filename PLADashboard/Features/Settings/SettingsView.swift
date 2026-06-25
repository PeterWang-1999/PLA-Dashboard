import SwiftUI

struct SettingsView: View {
    @Environment(AccountStore.self) private var accountStore
    @Environment(DashboardSettingsNotifier.self) private var dashboardSettingsNotifier

    @AppStorage(AppSettings.defaultPageSizeKey) private var defaultPageSize = 30

    @State private var showPurgeConfirmation = false
    @State private var pendingPurgeCount = 0
    @State private var isPurging = false
    @State private var purgeResultMessage: String?
    @State private var showPurgeResult = false

    var body: some View {
        let workspaceRevision = accountStore.workspaceRevision

        Group {
            if let accountID = accountStore.activeAccountID {
                accountScopedForm(accountID: accountID)
                    .id("\(accountID)-\(workspaceRevision)")
            } else {
                ContentUnavailableView {
                    Label("未选择账户", systemImage: "person.crop.circle.badge.questionmark")
                } description: {
                    Text("请先在主窗口选择或创建一个工作区账户。")
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 420)
        .navigationTitle("设置")
    }

    @ViewBuilder
    private func accountScopedForm(accountID: String) -> some View {
        let accountName = accountStore.activeAccount?.name ?? accountID

        Form {
            Section {
                LabeledContent("当前账户", value: accountName)
            } footer: {
                Text("以下预警与数据保留设置仅对当前账户生效。")
            }

            Section {
                Picker("每页行数", selection: $defaultPageSize) {
                    Text("20").tag(20)
                    Text("30").tag(30)
                    Text("50").tag(50)
                    Text("100").tag(100)
                }
                .pickerStyle(.radioGroup)
                .onChange(of: defaultPageSize) { _, _ in
                    dashboardSettingsNotifier.notifyChange()
                }
            } header: {
                Text("看板")
            } footer: {
                Text("每页行数为全局设置，更改后将在下次刷新看板时生效。")
            }

            Section {
                LabeledContent("高消高效 ROI 倍数") {
                    HStack(spacing: 8) {
                        Slider(
                            value: highEfficiencyROIMultiplierBinding(accountID: accountID),
                            in: 1.0...3.0,
                            step: 0.1
                        )
                        Text(String(
                            format: "%.1f×",
                            AppSettings.highEfficiencyROIMultiplier(accountID: accountID)
                        ))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                    }
                }

                Picker(
                    "低效最低点击",
                    selection: lowEfficiencyMinClicksBinding(accountID: accountID)
                ) {
                    Text("200").tag(200)
                    Text("250").tag(250)
                    Text("300").tag(300)
                    Text("400").tag(400)
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("预警分析")
            } footer: {
                Text("调整高效倍数与低效点击门槛后，看板将自动刷新预警标签。")
            }

            Section {
                Picker(
                    "Ads 日表保留",
                    selection: dataRetentionDaysBinding(accountID: accountID)
                ) {
                    Text("不限制").tag(0)
                    Text("60 天").tag(60)
                    Text("90 天").tag(90)
                    Text("180 天").tag(180)
                }
                .pickerStyle(.radioGroup)

                Button("立即清理过期数据…") {
                    Task { await preparePurgeConfirmation(accountID: accountID) }
                }
                .disabled(AppSettings.dataRetentionDays(accountID: accountID) == 0 || isPurging)
            } header: {
                Text("数据")
            } footer: {
                Text("仅删除当前账户 Google Ads 日表中早于保留期的行；产品主表与导入记录保留。清理后将自动重建周聚合。")
            }
        }
        .confirmationDialog(
            "确认清理过期数据？",
            isPresented: $showPurgeConfirmation,
            titleVisibility: .visible
        ) {
            Button("清理 \(pendingPurgeCount) 行", role: .destructive) {
                Task { await performPurge(accountID: accountID) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(
                "将删除 \(pendingPurgeCount) 行 ads_product_daily 记录（早于保留 \(AppSettings.dataRetentionDays(accountID: accountID)) 天）。"
            )
        }
        .alert("数据清理", isPresented: $showPurgeResult) {
            Button("好", role: .cancel) {}
        } message: {
            Text(purgeResultMessage ?? "")
        }
    }

    private func highEfficiencyROIMultiplierBinding(accountID: String) -> Binding<Double> {
        Binding(
            get: { AppSettings.highEfficiencyROIMultiplier(accountID: accountID) },
            set: { newValue in
                AppSettings.setHighEfficiencyROIMultiplier(newValue, accountID: accountID)
                dashboardSettingsNotifier.notifyChange()
            }
        )
    }

    private func lowEfficiencyMinClicksBinding(accountID: String) -> Binding<Int> {
        Binding(
            get: { AppSettings.lowEfficiencyMinClicks(accountID: accountID) },
            set: { newValue in
                AppSettings.setLowEfficiencyMinClicks(newValue, accountID: accountID)
                dashboardSettingsNotifier.notifyChange()
            }
        )
    }

    private func dataRetentionDaysBinding(accountID: String) -> Binding<Int> {
        Binding(
            get: { AppSettings.dataRetentionDays(accountID: accountID) },
            set: { newValue in
                AppSettings.setDataRetentionDays(newValue, accountID: accountID)
                AppSettings.setLastRetentionPurgeDay(nil, accountID: accountID)
                dashboardSettingsNotifier.notifyChange()
            }
        )
    }

    @MainActor
    private func preparePurgeConfirmation(accountID: String) async {
        let retentionDays = AppSettings.dataRetentionDays(accountID: accountID)
        guard retentionDays > 0 else { return }
        guard let client = accountStore.activeDatabaseClient,
              client.accountID == accountID else {
            purgeResultMessage = "数据库未就绪"
            showPurgeResult = true
            return
        }
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
    private func performPurge(accountID: String) async {
        let retentionDays = AppSettings.dataRetentionDays(accountID: accountID)
        guard let client = accountStore.activeDatabaseClient,
              client.accountID == accountID else {
            purgeResultMessage = "数据库未就绪"
            showPurgeResult = true
            return
        }
        isPurging = true
        defer { isPurging = false }
        do {
            let deleted = try await client.purgeExpiredAdsDaily(retentionDays: retentionDays)
            if let latestDay = try await client.fetchLatestMetricDay() {
                AppSettings.setLastRetentionPurgeDay(latestDay, accountID: accountID)
            }
            purgeResultMessage = "已删除 \(deleted) 行过期 Ads 日表数据，并已重建周聚合。"
            showPurgeResult = true
            dashboardSettingsNotifier.notifyChange()
        } catch {
            purgeResultMessage = error.localizedDescription
            showPurgeResult = true
        }
    }
}

#Preview {
    SettingsView()
        .environment(AccountStore())
        .environment(DashboardSettingsNotifier())
}
