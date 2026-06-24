import Foundation

struct WorkspaceAccountsManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var activeAccountID: String
    var accounts: [WorkspaceAccount]

    init(schemaVersion: Int, activeAccountID: String, accounts: [WorkspaceAccount]) {
        self.schemaVersion = schemaVersion
        self.activeAccountID = activeAccountID
        self.accounts = accounts
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw WorkspaceAccountError.unsupportedManifestVersion(schemaVersion)
        }
        guard !accounts.isEmpty else {
            throw WorkspaceAccountError.invalidManifest("账户列表不能为空")
        }

        let accountIDs = accounts.map(\.id)
        guard Set(accountIDs).count == accountIDs.count else {
            throw WorkspaceAccountError.invalidManifest("存在重复的账户 ID")
        }
        guard accounts.contains(where: { $0.id == activeAccountID }) else {
            throw WorkspaceAccountError.invalidManifest("当前选中账户不存在于账户列表")
        }

        for account in accounts {
            let trimmedName = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                throw WorkspaceAccountError.invalidManifest("账户名称不能为空")
            }
            guard trimmedName.count <= WorkspaceAccount.maxNameLength else {
                throw WorkspaceAccountError.invalidManifest("账户名称过长")
            }
        }
    }
}
