import SwiftUI

struct SettingsView: View {
    @Environment(AccountStore.self) private var accountStore

    @AppStorage(AppSettings.defaultPageSizeKey) private var defaultPageSize = 30
    @AppStorage(AppSettings.highEfficiencyROIMultiplierKey) private var highEfficiencyROIMultiplier = AnalyticsConfiguration.highEfficiencyROIMultiplier
    @AppStorage(AppSettings.lowEfficiencyMinClicksKey) private var lowEfficiencyMinClicks = AnalyticsConfiguration.lowEfficiencyMinClicks
    @AppStorage(AppSettings.dataRetentionDaysKey) private var dataRetentionDays = 0

    @State private var showPurgeConfirmation = false
    @State private var pendingPurgeCount = 0
    @State private var isPurging = false
    @State private var purgeResultMessage: String?
    @State private var showPurgeResult = false

    var body: some View {
        Form {
            Section {
                Picker("每页行数", selection: $defaultPageSize) {
                    Text("20").tag(20)
                    Text("30").tag(30)
                    Text("50").tag(50)
                    Text("100").tag(100)
                }
                .pickerStyle(.radioGroup)
                .onChange(of: defaultPageSize) { _, _ in
                    AppSettings.notifyDashboardSettingsDidChange()
                }
            } header: {
                Text("看板")
            } footer: {
                Text("更改后将在下次刷新看板时生效。")
            }

            Section {
                LabeledContent("高消高效 ROI 倍数") {
                    HStack(spacing: 8) {
                        Slider(value: $highEfficiencyROIMultiplier, in: 1.0...3.0, step: 0.1)
                        Text(String(format: "%.1f×", highEfficiencyROIMultiplier))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                .onChange(of: highEfficiencyROIMultiplier) { _, _ in
                    AppSettings.notifyDashboardSettingsDidChange()
                }

                Picker("低效最低点击", selection: $lowEfficiencyMinClicks) {
                    Text("200").tag(200)
                    Text("250").tag(250)
                    Text("300").tag(300)
                    Text("400").tag(400)
                }
                .pickerStyle(.radioGroup)
                .onChange(of: lowEfficiencyMinClicks) { _, _ in
                    AppSettings.notifyDashboardSettingsDidChange()
                }
            } header: {
                Text("预警分析")
            } footer: {
                Text("调整高效倍数与低效点击门槛后，看板将自动刷新预警标签。")
            }

            Section {
                Picker("Ads 日表保留", selection: $dataRetentionDays) {
                    Text("不限制").tag(0)
                    Text("60 天").tag(60)
                    Text("90 天").tag(90)
                    Text("180 天").tag(180)
                }
                .pickerStyle(.radioGroup)
                .onChange(of: dataRetentionDays) { _, _ in
                    AppSettings.lastRetentionPurgeDay = nil
                    AppSettings.notifyDashboardSettingsDidChange()
                }

                Button("立即清理过期数据…") {
                    Task { await preparePurgeConfirmation() }
                }
                .disabled(dataRetentionDays == 0 || isPurging)
            } header: {
                Text("数据")
            } footer: {
                Text("仅删除 Google Ads 日表中早于保留期的行；产品主表与导入记录保留。清理后将自动重建周聚合。")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 420)
        .navigationTitle("设置")
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
            Text("将删除 \(pendingPurgeCount) 行 ads_product_daily 记录（早于保留 \(dataRetentionDays) 天）。")
        }
        .alert("数据清理", isPresented: $showPurgeResult) {
            Button("好", role: .cancel) {}
        } message: {
            Text(purgeResultMessage ?? "")
        }
    }

    @MainActor
    private func preparePurgeConfirmation() async {
        guard dataRetentionDays > 0 else { return }
        guard let client = accountStore.activeDatabaseClient else {
            purgeResultMessage = "数据库未就绪"
            showPurgeResult = true
            return
        }
        isPurging = true
        defer { isPurging = false }
        do {
            pendingPurgeCount = try await client.countExpiredAdsDailyRows(retentionDays: dataRetentionDays)
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
        guard let client = accountStore.activeDatabaseClient else {
            purgeResultMessage = "数据库未就绪"
            showPurgeResult = true
            return
        }
        isPurging = true
        defer { isPurging = false }
        do {
            let deleted = try await client.purgeExpiredAdsDaily(retentionDays: dataRetentionDays)
            if let latestDay = try await client.fetchLatestMetricDay() {
                AppSettings.lastRetentionPurgeDay = latestDay
            }
            purgeResultMessage = "已删除 \(deleted) 行过期 Ads 日表数据，并已重建周聚合。"
            showPurgeResult = true
            AppSettings.notifyDashboardSettingsDidChange()
        } catch {
            purgeResultMessage = error.localizedDescription
            showPurgeResult = true
        }
    }
}

#Preview {
    SettingsView()
}
