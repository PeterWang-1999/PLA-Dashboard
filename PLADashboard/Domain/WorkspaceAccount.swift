import Foundation

struct WorkspaceAccount: Codable, Identifiable, Equatable, Sendable {
    static let maxNameLength = 64

    var id: String
    var name: String
    var kind: WorkspaceAccountKind
    var createdAt: Date

    static func makeDefault(name: String, kind: WorkspaceAccountKind = .thirdParty) -> WorkspaceAccount {
        WorkspaceAccount(
            id: UUID().uuidString,
            name: name,
            kind: kind,
            createdAt: Date()
        )
    }
}
