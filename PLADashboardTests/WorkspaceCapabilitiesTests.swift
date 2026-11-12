import XCTest
@testable import PLADashboard

final class WorkspaceCapabilitiesTests: XCTestCase {
    func testThirdPartyImportKinds() {
        let capabilities = WorkspaceCapabilities.forKind(.thirdParty)
        XCTAssertEqual(capabilities.importSourceKinds, [.merchantCenter, .adsProduct])
        XCTAssertFalse(capabilities.importSourceKinds.contains(.salesReport))
    }

    func testSelfBuiltImportKinds() {
        let capabilities = WorkspaceCapabilities.forKind(.selfBuilt)
        XCTAssertEqual(
            capabilities.importSourceKinds,
            [.merchantCenter, .salesReport]
        )
        XCTAssertFalse(capabilities.importSourceKinds.contains(.adsProduct))
    }

    func testDownloadsAreAvailableOnlyForSelfBuiltAccounts() {
        let thirdParty = WorkspaceCapabilities.forKind(.thirdParty)
        let selfBuilt = WorkspaceCapabilities.forKind(.selfBuilt)
        XCTAssertEqual(selfBuilt.sidebarNavigationItems, AppNavigationItem.defaultSidebarCases + [.downloads])
        XCTAssertEqual(thirdParty.sidebarNavigationItems, AppNavigationItem.defaultSidebarCases)
        XCTAssertEqual(
            AppNavigationItem.defaultSidebarCases,
            [.dashboard, .dataDashboard, .imports]
        )
    }

    func testImportPickerCasesShimMatchesCapabilities() {
        XCTAssertEqual(
            ImportSourceKind.importPickerCases(for: .thirdParty),
            WorkspaceCapabilities.forKind(.thirdParty).importSourceKinds
        )
        XCTAssertEqual(
            ImportSourceKind.importPickerCases(for: .selfBuilt),
            WorkspaceCapabilities.forKind(.selfBuilt).importSourceKinds
        )
    }
}
