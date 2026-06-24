import SwiftUI

struct CreateAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountStore.self) private var accountStore

    let isImportInProgress: Bool

    @State private var accountName = ""
    @State private var creationError: String?
    @State private var isCreating = false

    var body: some View {
        Form {
            Section {
                TextField("账户名称", text: $accountName)
                    .textFieldStyle(.roundedBorder)
            } footer: {
                if let creationError {
                    Text(creationError)
                        .foregroundStyle(.red)
                } else if isImportInProgress {
                    Text("导入进行中时创建账户不会自动切换，可在导入完成后再切换。")
                } else {
                    Text("新账户默认为三方站类型，可在创建后开始导入数据。")
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 360, minHeight: 160)
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

    @MainActor
    private func createAccount() async {
        guard isNameValid else { return }

        isCreating = true
        creationError = nil
        defer { isCreating = false }

        do {
            let account = try accountStore.createAccount(name: trimmedName, kind: .thirdParty)
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
