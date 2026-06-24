import SwiftUI

struct CreateAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountStore.self) private var accountStore

    let isImportInProgress: Bool

    @State private var accountName = ""
    @State private var selectedKind: WorkspaceAccountKind = .thirdParty
    @State private var creationError: String?
    @State private var isCreating = false

    var body: some View {
        Form {
            Section {
                TextField("账户名称", text: $accountName)
                    .textFieldStyle(.roundedBorder)
            }

            Section {
                Picker("账户类型", selection: $selectedKind) {
                    ForEach(WorkspaceAccountKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.radioGroup)
            } footer: {
                if let creationError {
                    Text(creationError)
                        .foregroundStyle(.red)
                } else if isImportInProgress {
                    Text("导入进行中时创建账户不会自动切换，可在导入完成后再切换。")
                } else {
                    Text(kindFooter)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 360, minHeight: 220)
        .navigationTitle("新建账户")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    dismiss()
                }
                .disabled(isCreating)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("创建") {
                    Task { await createAccount() }
                }
                .disabled(!isNameValid || isCreating)
            }
        }
    }

    private var trimmedName: String {
        accountName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isNameValid: Bool {
        !trimmedName.isEmpty && trimmedName.count <= WorkspaceAccount.maxNameLength
    }

    private var kindFooter: String {
        switch selectedKind {
        case .thirdParty:
            "三方站支持 Merchant Center 与 Google Ads 导入。"
        case .selfBuilt:
            "自建站额外支持 Product Sales 导入；看板「销售趋势」仍来自 Google Ads 转化价值。"
        }
    }

    @MainActor
    private func createAccount() async {
        guard isNameValid else { return }

        isCreating = true
        creationError = nil
        defer { isCreating = false }

        do {
            let account = try accountStore.createAccount(name: trimmedName, kind: selectedKind)
            if !isImportInProgress {
                try await accountStore.switchAccount(to: account.id, isImportInProgress: false)
            }
            dismiss()
        } catch {
            creationError = error.localizedDescription
        }
    }
}

#Preview {
    CreateAccountSheet(isImportInProgress: false)
        .environment(AccountStore())
}
