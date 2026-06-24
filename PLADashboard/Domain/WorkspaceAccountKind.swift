import Foundation

enum WorkspaceAccountKind: String, Codable, Sendable, CaseIterable {
    case selfBuilt = "self_built"
    case thirdParty = "third_party"

    var displayName: String {
        switch self {
        case .selfBuilt: "自建站"
        case .thirdParty: "三方站"
        }
    }
}
