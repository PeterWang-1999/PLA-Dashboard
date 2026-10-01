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

        Form {
            Section {
                LabeledContent("当前账户", value: accountName)
            } footer: {
                Text("以下数据保留设置仅对当前账户生效。")
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
        }
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
