import XCTest
@testable import PLADashboard

@MainActor
final class DashboardSettingsNotifierTests: XCTestCase {
    func testNotifyChangeIncrementsRevision() {
        let notifier = DashboardSettingsNotifier()
        XCTAssertEqual(notifier.revision, 0)

        notifier.notifyChange()
        XCTAssertEqual(notifier.revision, 1)

        notifier.notifyChange()
        XCTAssertEqual(notifier.revision, 2)
    }
}

@MainActor
final class ImportViewModelAccountResetTests: XCTestCase {
    func testResetForAccountSwitchClearsImportingState() {
        let viewModel = ImportViewModel()
        viewModel.isImporting = true
        viewModel.showFileImporter = true
        viewModel.errorMessage = "测试"

        viewModel.resetForAccountSwitch()

        XCTAssertFalse(viewModel.isImporting)
        XCTAssertFalse(viewModel.showFileImporter)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.importJobs.isEmpty)
    }
}
