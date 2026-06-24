import Foundation
@testable import PLADashboard

enum WorkspaceTestSupport {
    @discardableResult
    static func setUpTemporaryWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pla-workspace-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        WorkspacePaths.testRootOverride = root
        return root
    }

    static func tearDownTemporaryWorkspace(root: URL) {
        WorkspacePaths.testRootOverride = nil
        try? FileManager.default.removeItem(at: root)
    }
}
