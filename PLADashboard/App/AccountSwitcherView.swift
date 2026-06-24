import SwiftUI

struct AccountSwitcherView: View {
    @Environment(AccountStore.self) private var accountStore

    let isImportInProgress: Bool
    var onSwitchBlocked: () -> Void

    @State private var isPresentingCreateSheet = false
    @State private var isSwitching = false
    @State private var actionErrorMessage: String?

    var body: some View {
        Menu {
            ForEach(accountStore.accounts) { account in
                Button {
                    switchTo(account.id)
                } label: {
                    if account.id == accountStore.activeAccountID {
                        Label(account.name, systemImage: "checkmark")
                    } else {
                        Text(account.name)
                    }
                }
            }

            Divider()

            Button("新建账户…") {
                isPresentingCreateSheet = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(.secondary)

                Text(activeAccountName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isSwitching {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .disabled(isSwitching)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("当前账户")
        .accessibilityValue(activeAccountName)
        .help("切换或新建账户")
        .sheet(isPresented: $isPresentingCreateSheet) {
            NavigationStack {
                CreateAccountSheet(isImportInProgress: isImportInProgress)
            }
            .environment(accountStore)
        }
        .alert("操作失败", isPresented: actionErrorPresented) {
            Button("好", role: .cancel) {
                actionErrorMessage = nil
            }
        } message: {
            if let actionErrorMessage {
                Text(actionErrorMessage)
            }
        }
    }

    private var activeAccountName: String {
        accountStore.activeAccount?.name ?? "未选择账户"
    }

    private var actionErrorPresented: Binding<Bool> {
        Binding(
            get: { actionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    actionErrorMessage = nil
                }
            }
        )
    }

    private func switchTo(_ accountID: String) {
        guard accountID != accountStore.activeAccountID else { return }
        if isImportInProgress {
            onSwitchBlocked()
            return
        }

        isSwitching = true
        Task {
            defer { isSwitching = false }
            do {
                try await accountStore.switchAccount(to: accountID, isImportInProgress: false)
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }
}
