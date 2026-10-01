import XCTest
@testable import PLADashboard

@MainActor
final class WorkspaceAccountServiceTests: XCTestCase {
    func testBootstrapLeavesMainActorResponsiveAndInitializesOnlyOnce() async throws {
        let root = try WorkspaceTestSupport.setUpTemporaryWorkspace()
        defer { WorkspaceTestSupport.tearDownTemporaryWorkspace(root: root) }
        let started = expectation(description: "background database open started")
        let probe = WorkspaceOpenProbe(blockedOpen: 1, started: started)
        defer { probe.release() }
        let service = WorkspaceAccountService { accountID in
            probe.recordOpen()
            return try DatabaseClient.make(accountID: accountID)
        }
        let store = AccountStore(workspaceService: service)
        let firstWindow = Task { await store.bootstrap() }
        await fulfillment(of: [started], timeout: 3)

        // 后台数据库打开尚未完成时，MainActor 可以运行这里的代码。
        XCTAssertEqual(store.phase, .loading)
        XCTAssertFalse(probe.usedMainThread)
        await store.bootstrap() // 第二个窗口不重复初始化。
        XCTAssertEqual(probe.openCount, 1)
        probe.release()
        await firstWindow.value
        XCTAssertEqual(store.phase, .ready)
        let revision = store.workspaceRevision
        await store.bootstrap()
        XCTAssertEqual(probe.openCount, 1)
        XCTAssertEqual(store.workspaceRevision, revision)
    }

    func testSwitchOpensOffMainActorAndBlocksConcurrentCreation() async throws {
        let root = try WorkspaceTestSupport.setUpTemporaryWorkspace()
        defer { WorkspaceTestSupport.tearDownTemporaryWorkspace(root: root) }
        let started = expectation(description: "background switch started")
        let probe = WorkspaceOpenProbe(blockedOpen: 2, started: started)
        defer { probe.release() }
        let store = AccountStore(workspaceService: WorkspaceAccountService { accountID in
            probe.recordOpen()
            return try DatabaseClient.make(accountID: accountID)
        })
        await store.bootstrap()
        let originalID = store.activeAccountID
        let target = try await store.createAccount(name: "后台账户")
        let switchTask = Task { try await store.switchAccount(to: target.id) }
        await fulfillment(of: [started], timeout: 3)
        XCTAssertTrue(store.isSwitchingAccount)
        XCTAssertEqual(store.activeAccountID, originalID)
        XCTAssertFalse(probe.usedMainThread)
        do {
            _ = try await store.createAccount(name: "并发账户")
            XCTFail("切换尚未完成时应拒绝创建，避免配置写入交叠")
        } catch {
            guard case WorkspaceAccountError.workspaceChanged = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        probe.release()
        try await switchTask.value
        XCTAssertEqual(store.activeAccountID, target.id)
        XCTAssertEqual(store.activeDatabaseClient?.accountID, target.id)
        XCTAssertFalse(store.isSwitchingAccount)
    }

    func testFailedSwitchPreservesInMemoryAndPersistedAccount() async throws {
        let root = try WorkspaceTestSupport.setUpTemporaryWorkspace()
        defer { WorkspaceTestSupport.tearDownTemporaryWorkspace(root: root) }
        let probe = WorkspaceOpenProbe()
        let store = AccountStore(workspaceService: WorkspaceAccountService { accountID in
            let count = probe.recordOpen()
            if count > 1 { throw CocoaError(.fileReadCorruptFile) }
            return try DatabaseClient.make(accountID: accountID)
        })
        await store.bootstrap()
        let originalID = store.activeAccountID
        let revision = store.workspaceRevision
        let target = try await store.createAccount(name: "无法打开")
        do {
            try await store.switchAccount(to: target.id)
            XCTFail("Expected open failure")
        } catch {
            XCTAssertEqual(store.phase, .ready)
            XCTAssertFalse(store.isSwitchingAccount)
            XCTAssertEqual(store.activeAccountID, originalID)
            XCTAssertEqual(store.activeDatabaseClient?.accountID, originalID)
            XCTAssertEqual(store.workspaceRevision, revision)
            XCTAssertEqual(try WorkspaceAccountPersistence.load()?.activeAccountID, originalID)
        }
    }

    func testBootstrapFailureCanRetry() async throws {
        let root = try WorkspaceTestSupport.setUpTemporaryWorkspace()
        defer { WorkspaceTestSupport.tearDownTemporaryWorkspace(root: root) }
        let probe = WorkspaceOpenProbe()
        let store = AccountStore(workspaceService: WorkspaceAccountService { accountID in
            if probe.recordOpen() == 1 { throw CocoaError(.fileReadCorruptFile) }
            return try DatabaseClient.make(accountID: accountID)
        })
        await store.bootstrap()
        guard case .failed = store.phase else { return XCTFail("Expected failed phase") }
        XCTAssertNil(store.activeDatabaseClient)
        await store.bootstrap()
        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(probe.openCount, 2)
        XCTAssertFalse(probe.usedMainThread)
    }
}

/// 仅用于测试：锁保护计数，门闩让测试确定性地检查初始化期间的 UI 响应。
private final class WorkspaceOpenProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private let blockedOpen: Int?
    private let started: XCTestExpectation?
    private var count = 0
    private var mainThread = false

    init(blockedOpen: Int? = nil, started: XCTestExpectation? = nil) {
        self.blockedOpen = blockedOpen
        self.started = started
    }

    var openCount: Int { lock.withLock { count } }
    var usedMainThread: Bool { lock.withLock { mainThread } }

    @discardableResult
    func recordOpen() -> Int {
        let current = lock.withLock {
            count += 1
            mainThread = mainThread || Thread.isMainThread
            return count
        }
        if current == blockedOpen {
            started?.fulfill()
            _ = gate.wait(timeout: .now() + 5)
        }
        return current
    }

    func release() { gate.signal() }
}
