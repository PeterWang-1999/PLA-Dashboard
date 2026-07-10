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
            [.merchantCenter, .plaDeliveryDetail, .salesReport]
        )
        XCTAssertFalse(capabilities.importSourceKinds.contains(.adsProduct))
    }

    func testSidebarItemsEqualForV1() {
        let thirdParty = WorkspaceCapabilities.forKind(.thirdParty)
        let selfBuilt = WorkspaceCapabilities.forKind(.selfBuilt)
        XCTAssertEqual(thirdParty.sidebarNavigationItems, selfBuilt.sidebarNavigationItems)
        XCTAssertEqual(thirdParty.sidebarNavigationItems, AppNavigationItem.defaultSidebarCases)
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
