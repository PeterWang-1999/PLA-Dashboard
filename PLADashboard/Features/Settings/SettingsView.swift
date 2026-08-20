import SwiftUI

struct SettingsView: View {
    @Environment(AccountStore.self) private var accountStore
    @Environment(DashboardSettingsNotifier.self) private var dashboardSettingsNotifier

    @AppStorage(AppSettings.defaultPageSizeKey) private var defaultPageSize = 30

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
        let isSelfBuilt = accountStore.activeAccount?.kind == .selfBuilt

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

            if !isSelfBuilt {
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
            } header: {
                Text("数据")
            } footer: {
                Text("产品数据页面底栏的“数据维护”菜单可清理当前账户中超过保留期的 Ads 日表；产品主表与导入记录始终保留。")
            }

            ProductImageDiagnosticsSection(accountID: accountID, accountName: accountName)
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
}

#Preview {
    SettingsView()
        .environment(AccountStore())
        .environment(DashboardSettingsNotifier())
}
