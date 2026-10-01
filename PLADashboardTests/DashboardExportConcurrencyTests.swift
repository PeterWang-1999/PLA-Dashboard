import XCTest
@testable import PLADashboard

@MainActor
final class DashboardExportConcurrencyTests: XCTestCase {
    private func model(_ loader: ControlledExportLoader) throws -> DashboardViewModel {
        let model = DashboardViewModel(exportLoader: { _, filters in try await loader.load(filters) })
        model.configure(databaseClient: try DatabaseClient.makeInMemoryForTesting())
        model.bootstrapDataSource(hasMetrics: true)
        return model
    }

    private var bundle: DashboardExportBundle {
        DashboardExportBundle(rows: [DashboardPreviewData.rows[0]], weekStarts: ["2026-09-20"], totalCount: 1)
    }

    func testFilterChangesDuringExportKeepOriginalMetadata() async throws {
        let loader = ControlledExportLoader()
        let model = try model(loader)
        model.searchText = "original"
        let task = Task { try await model.prepareExport(includeClicksAndConversions: true) }
        await loader.wait(1)
        model.searchText = "changed"
        await loader.finish(1, .success(bundle))
        let document = try await task.value
        let filters = await loader.filters(1)
        XCTAssertEqual(filters.searchText, "original")
        XCTAssertTrue(document.text.contains("# search=\"original\""))
        XCTAssertFalse(document.text.contains("# search=\"changed\""))
        XCTAssertTrue(document.text.contains("# weeks=2026-09-20"))
        XCTAssertFalse(model.isExporting)
    }

    func testAccountResetDiscardsOldExportAndPreservesNewLoadingState() async throws {
        let loader = ControlledExportLoader()
        let model = try model(loader)
        let old = Task { try await model.prepareExport(includeClicksAndConversions: false) }
        await loader.wait(1)
        model.resetForAccountSwitch()
        model.configure(databaseClient: try DatabaseClient.makeInMemoryForTesting())
        model.bootstrapDataSource(hasMetrics: true)
        let latest = Task { try await model.prepareExport(includeClicksAndConversions: false) }
        await loader.wait(2)
        await loader.finish(1, .success(bundle))
        do { _ = try await old.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(model.isExporting)
        await loader.finish(2, .success(bundle))
        _ = try await latest.value
        XCTAssertFalse(model.isExporting)
    }

    func testOldAccountFailureIsDiscarded() async throws {
        let loader = ControlledExportLoader()
        let model = try model(loader)
        let task = Task { try await model.prepareExport(includeClicksAndConversions: false) }
        await loader.wait(1)
        model.resetForAccountSwitch()
        await loader.finish(1, .failure(URLError(.timedOut)))
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(model.isExporting)
    }

    func testCancelledExportDoesNotProduceDocument() async throws {
        let loader = ControlledExportLoader()
        let model = try model(loader)
        let task = Task { try await model.prepareExport(includeClicksAndConversions: false) }
        await loader.wait(1)
        task.cancel()
        await loader.finish(1, .success(bundle))
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(model.isExporting)
    }

    func testCancelledExportFailureIsNotDisplayed() async throws {
        let loader = ControlledExportLoader()
        let model = try model(loader)
        let task = Task { try await model.prepareExport(includeClicksAndConversions: false) }
        await loader.wait(1)
        task.cancel()
        await loader.finish(1, .failure(URLError(.timedOut)))
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(model.isExporting)
    }

    func testSaveFailureFeedbackDistinguishesCancellation() {
        XCTAssertNil(ExportSaveFeedback.message(for: .success(URL(fileURLWithPath: "/tmp/export.csv"))))
        XCTAssertNil(ExportSaveFeedback.message(for: .failure(CancellationError())))
        XCTAssertNil(ExportSaveFeedback.message(for: .failure(CocoaError(.userCancelled))))
        XCTAssertNotNil(ExportSaveFeedback.message(for: .failure(CocoaError(.fileWriteNoPermission))))
        XCTAssertNotNil(ExportSaveFeedback.message(for: .failure(CocoaError(.fileWriteOutOfSpace))))
    }
}

private actor ControlledExportLoader {
    private var requests: [DashboardQueryFilters] = []
    private var pending: [Int: CheckedContinuation<DashboardExportBundle, Error>] = [:]
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []

    func load(_ filters: DashboardQueryFilters) async throws -> DashboardExportBundle {
        try await withCheckedThrowingContinuation { continuation in
            requests.append(filters)
            pending[requests.count] = continuation
            let ready = observers.filter { $0.0 <= requests.count }
            observers.removeAll { $0.0 <= requests.count }
            for (_, observer) in ready { observer.resume() }
        }
    }

    func filters(_ number: Int) -> DashboardQueryFilters { requests[number - 1] }
    func wait(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { observers.append((count, $0)) }
    }
    func finish(_ number: Int, _ result: Result<DashboardExportBundle, Error>) {
        pending.removeValue(forKey: number)?.resume(with: result)
    }
}
