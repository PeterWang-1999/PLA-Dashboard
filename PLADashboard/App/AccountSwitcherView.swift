import SwiftUI

struct AccountSwitcherView: View {
    @Environment(AccountStore.self) private var accountStore

    let isImportInProgress: Bool
    var onSwitchBlocked: () -> Void

    @State private var isPresentingAccountPicker = false
    @State private var isPresentingCreateSheet = false
    @State private var isSwitching = false
    @State private var actionErrorMessage: String?

    var body: some View {
        Button {
            isPresentingAccountPicker = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(activeAccountName)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(activeAccountKindName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)

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
        .buttonStyle(.plain)
        .disabled(isSwitching)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("当前账户")
        .accessibilityValue("\(activeAccountName)，\(activeAccountKindName)")
        .help("切换或新建账户")
        .popover(isPresented: $isPresentingAccountPicker, arrowEdge: .top) {
            accountPicker
        }
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

    private var accountPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(accountStore.accounts) { account in
                Button {
                    isPresentingAccountPicker = false
                    switchTo(account.id)
                } label: {
                    HStack {
                        Text(account.name)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if account.id == accountStore.activeAccountID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            Divider()

            Button("新建账户…") {
                isPresentingAccountPicker = false
                isPresentingCreateSheet = true
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .padding(.vertical, 4)
        .frame(minWidth: 200)
    }

    private var activeAccountName: String {
        accountStore.activeAccount?.name ?? "未选择账户"
    }

    private var activeAccountKindName: String {
        accountStore.activeAccount?.kind.displayName ?? "未知类型"
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
