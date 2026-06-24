import SwiftUI

struct SettingsView: View {
    @AppStorage("dashboard.defaultPageSize") private var defaultPageSize = 30

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
            } header: {
                Text("看板")
            } footer: {
                Text("更改后将在下次刷新看板时生效。")
            }

            Section {
                LabeledContent("数据保留") {
                    Text("本地存储")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("数据")
            } footer: {
                Text("数据保留策略将在后续版本提供可配置选项。")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 240)
        .navigationTitle("设置")
    }
}

#Preview {
    SettingsView()
}
