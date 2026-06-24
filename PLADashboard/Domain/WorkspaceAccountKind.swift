import Foundation

enum WorkspaceAccountKind: String, Codable, Sendable, CaseIterable {
    case selfBuilt = "self_built"
    case thirdParty = "third_party"
}
