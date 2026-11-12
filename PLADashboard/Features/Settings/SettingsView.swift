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
                Text("品类和数据保留设置仅对当前账户生效。")
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

            if accountStore.activeAccount?.kind == .selfBuilt {
                BIDefaultCategorySettings(accountID: accountID)
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

private struct BIDefaultCategorySettings: View {
    @Environment(BIDownloadStore.self) private var downloads
    @State private var draft = BIFilters()
    @State private var categories: [BICategory] = []
    @State private var error: String?
    @State private var refresh = 0
    @State private var isLoading = true

    let accountID: String

    private var saved: [BICategory]? { downloads.workspace(accountID).defaultCategories }
    private var hasChanges: Bool {
        draft.category.isEmpty && draft.selectedCategories != saved
    }

    var body: some View {
        Section {
            LabeledContent("默认品类") {
                BICategoryPicker(categories: categories, filters: $draft)
                    .disabled(isLoading || categories.isEmpty)
            }
            if isLoading {
                ProgressView("正在加载 BI Data 品类…").controlSize(.small)
            } else if let error {
                HStack {
                    Text(error).foregroundStyle(.secondary)
                    Spacer()
                    Button("重试") { refresh += 1 }
                }
            }
            HStack {
                Button("恢复 Toys & Games") {
                    draft = draft.usingDefaultCategories(nil)
                    if !downloads.resetDefaultCategories(accountID: accountID) {
                        error = "无法恢复默认品类。"
                    }
                }
                .disabled(saved == nil)
                Spacer()
                Button("保存品类") {
                    guard let selected = draft.selectedCategories else { return }
                    error = downloads.saveDefaultCategories(selected, accountID: accountID) ? nil : "无法保存默认品类。"
                }
                .disabled(isLoading || !hasChanges || draft.selectedCategories?.isEmpty != false)
            }
        } header: {
            Text("BI Data")
        } footer: {
            Text("同步数据和默认下载预设使用这些品类。可以同时选择同一层级的多个品类。")
        }
        .task(id: refresh) {
            draft = BIFilters().usingDefaultCategories(saved)
            isLoading = true
            error = nil
            defer { isLoading = false }
            do {
                categories = try await downloads.loadFilterOptions(for: accountID, merchant: "LITB").categoryTree ?? []
            } catch is CancellationError {
            } catch let failure {
                error = failure.localizedDescription
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AccountStore())
        .environment(DashboardSettingsNotifier())
        .environment(BIDownloadStore())
}
