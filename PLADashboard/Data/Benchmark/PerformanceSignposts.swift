import Foundation
import os

/// Instruments / MetricKit 关联用性能标记（`OSSignpost`）。
enum PerformanceSignposts {
    private static let log = OSLog(subsystem: "com.pla.dashboard", category: "Performance")

    static func beginImportFlush() -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "import.flush", signpostID: id)
        return id
    }

    static func endImportFlush(_ id: OSSignpostID) {
        os_signpost(.end, log: log, name: "import.flush", signpostID: id)
    }

    static func beginETLRebuild() -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "etl.rebuild", signpostID: id)
        return id
    }

    static func endETLRebuild(_ id: OSSignpostID) {
        os_signpost(.end, log: log, name: "etl.rebuild", signpostID: id)
    }

    static func beginDashboardFetchPage() -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "dashboard.fetchPage", signpostID: id)
        return id
    }

    static func endDashboardFetchPage(_ id: OSSignpostID) {
        os_signpost(.end, log: log, name: "dashboard.fetchPage", signpostID: id)
    }
}
