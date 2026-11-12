import Foundation
import WebKit

@MainActor
final class BIWebSession: NSObject, WKUIDelegate, WKNavigationDelegate, WKDownloadDelegate {
    struct Failure: LocalizedError {
        let status: BIDownloadRun.Status
        let message: String

        var errorDescription: String? { message }
    }

    let webView: WKWebView
    let portal: URL
    private var download: WKDownload?
    private var downloadResult: Result<Void, Failure>?
    private var destination: URL?
    private var triedOpeningReport = false

    init(portal: URL, accountID: UUID, allowsLoginLayout: Bool = false) {
        self.portal = portal
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: accountID)
        if allowsLoginLayout {
            configuration.userContentController.addUserScript(WKUserScript(
                source: Self.loginLayoutScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false,
                in: .defaultClient
            ))
        }
        // Background sessions still need the desktop layout to expose the portal and report controls.
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1400, height: 900), configuration: configuration)
        super.init()
        webView.uiDelegate = self
        webView.navigationDelegate = self
    }

    private static let loginLayoutScript = """
    const style = document.createElement("style");
    style.textContent = `
        html:has(input[type="password"]) { overflow-y: auto !important; }
        body:has(input[type="password"]) { height: auto !important; overflow-y: visible !important; }
    `;
    document.head?.appendChild(style);
    """

    func open() {
        triedOpeningReport = false
        webView.load(URLRequest(url: portal))
    }

    func isAuthenticated() async throws -> Bool {
        guard matchesPortal(webView.url), !webView.isLoading else { return false }
        return try await evaluate("authenticated") as? Bool == true
    }

    func waitForAuthentication() async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(12)
        while ContinuousClock.now < deadline {
            if try await isAuthenticated() { return true }
            try await Task.sleep(for: .milliseconds(500))
        }
        return false
    }

    private func reportIsReady() async throws -> Bool {
        guard matchesPortal(webView.url), !webView.isLoading else { return false }
        let ready = try await evaluate("ready", arguments: ["open": !triedOpeningReport])
        if ready as? String == "opening" { triedOpeningReport = true }
        return ready as? Bool == true
    }

    func options(merchant: String?) async throws -> BIFilterOptions {
        try await waitForReport(timeout: .seconds(12))
        let arguments = merchant.map { ["merchant": $0] } ?? [:]
        let response = try await evaluate("options", arguments: arguments)
        guard let dictionary = response as? [String: Any] else {
            throw Failure(status: .failed, message: "BI Data 筛选项格式无效。")
        }
        let data = try JSONSerialization.data(withJSONObject: dictionary)
        return try JSONDecoder().decode(BIFilterOptions.self, from: data)
    }

    func export(
        _ run: BIDownloadRun,
        to output: URL,
        onSubmissionStarted: () -> Void,
        progress: (BIDownloadRun.Status) -> Void
    ) async throws {
        let files = FileManager.default
        if files.fileExists(atPath: output.path) {
            try Self.validateReport(at: output, for: run)
            return
        }
        try files.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        if run.reportKind == .productDetail {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                let parameters = try await productExportParameters(filters: run.productDetailExportFilters)
                try Task.checkCancellation()
                onSubmissionStarted()
                progress(.downloading)
                try await downloadReport(to: output, for: run) {
                    let downloaded = try await evaluate("downloadProduct", arguments: ["parameters": parameters])
                    guard downloaded as? Bool == true else {
                        throw Failure(status: .failed, message: "BI Data 未返回有效的投放产品明细 XLSX。")
                    }
                }
            } onCancel: {
                Task { @MainActor in
                    self.webView.stopLoading()
                    _ = try? await self.evaluate("cancelExport")
                }
            }
            return
        }
        if run.reportKind == .productSales {
            try await withTaskCancellationHandler {
                try await requireAuthentication()
                try Task.checkCancellation()
                let filters = try JSONSerialization.jsonObject(with: JSONEncoder().encode(run.filters))
                let arguments = ["task": run.remoteTaskName, "filters": filters]
                let result = try await evaluate("submitSales", arguments: arguments) as? Int
                try Task.checkCancellation()
                guard let result, result > 0 else {
                    throw Failure(status: .failed, message: "Product Sales 未接受导出请求，可能已有相同筛选的任务正在生成。")
                }
                onSubmissionStarted()
                try await downloadQueuedReport(
                    run, to: output, exportName: "product_sales_detail", exportID: String(result), progress: progress
                )
            } onCancel: {
                Task { @MainActor in
                    self.webView.stopLoading()
                    _ = try? await self.evaluate("cancelExport")
                }
            }
            return
        }
        try await waitForReport(timeout: .seconds(20))

        let marker = output.deletingPathExtension().appendingPathExtension("submitted")
        let task = ["task": run.remoteTaskName]
        if !files.fileExists(atPath: marker.path) {
            let data = try JSONEncoder().encode(run.filters)
            let filters = try JSONSerialization.jsonObject(with: data)
            _ = try await evaluate("prepare", arguments: ["task": run.remoteTaskName, "filters": filters])
            // Record the attempt before confirmation so retry never submits a second task.
            try Data(run.remoteTaskName.utf8).write(to: marker, options: .atomic)
            _ = try await evaluate("confirm", arguments: task)
        }
        onSubmissionStarted()
        try await downloadQueuedReport(run, to: output, exportName: run.reportKind.rawValue, progress: progress)
    }

    private func downloadQueuedReport(
        _ run: BIDownloadRun, to output: URL, exportName: String, exportID: String = "",
        progress: (BIDownloadRun.Status) -> Void
    ) async throws {
        let task = ["task": run.remoteTaskName, "exportName": exportName, "exportID": exportID]
        let deadline = ContinuousClock.now + .seconds(300)
        var sawRemoteTask = false
        var checkedList = false
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            let result = try await evaluate("checkDownload", arguments: task) as? [String: String]
            switch result?["status"] {
            case "ready":
                guard let link = result?["url"], let url = URL(string: link),
                      matchesPortal(url), url.path == "/common2/DownFile" else {
                    throw Failure(status: .failed, message: "BI Data 返回了无法识别的下载地址。")
                }
                progress(.downloading)
                try await downloadReport(to: output, for: run) {
                    let active = await webView.startDownload(using: URLRequest(url: url))
                    trackDownload(active)
                }
                return
            case "pending":
                checkedList = true
                if !sawRemoteTask { progress(.generating) }
                sawRemoteTask = true
            case "missing":
                checkedList = true
            case "failed":
                throw Failure(status: .failed, message: "BI Data 下载列表显示该任务未完成导出。")
            case "ambiguous":
                throw Failure(status: .failed, message: "BI Data 下载列表有多条同名记录，无法确认本次文件。")
            default:
                if try await signInFormIsVisible() {
                    throw Failure(status: .needsLogin, message: "BI Data 显示了公司登录表单，请重新登录后重试。")
                }
            }
            try await Task.sleep(for: .seconds(3))
        }
        if !checkedList {
            throw Failure(status: .connectionFailed, message: "无法读取 BI Data 下载列表。重试会继续查询原任务。")
        }
        if !sawRemoteTask {
            throw Failure(status: .failed, message: "BI Data 下载列表尚未出现这条任务。重试会继续查询原任务。")
        }
        throw Failure(status: .failed, message: "报表仍未就绪。重试时会继续查询本次任务。")
    }

    private func productExportParameters(filters: BIFilters) async throws -> [String: Any] {
        if let restriction = filters.productDetailRestriction {
            throw Failure(status: .failed, message: restriction)
        }
        try await requireAuthentication()
        let encoded = try JSONEncoder().encode(filters)
        let arguments = ["filters": try JSONSerialization.jsonObject(with: encoded)]
        guard let parameters = try await evaluate("productParameters", arguments: arguments) as? [String: Any] else {
            throw Failure(status: .failed, message: "无法生成投放产品明细的导出参数。")
        }
        return parameters
    }

    private func requireAuthentication() async throws {
        guard try await waitForAuthentication() else {
            if try await signInFormIsVisible() {
                throw Failure(status: .needsLogin, message: "BI Data 显示了公司登录表单，请重新登录后重试。")
            }
            throw Failure(status: .connectionFailed, message: "未能连接 BI Data，请检查网络连接后重试。")
        }
    }

    func waitForReport(timeout: Duration) async throws {
        let deadline = ContinuousClock.now + timeout
        repeat {
            if try await reportIsReady() { return }
            guard ContinuousClock.now < deadline else { break }
            try await Task.sleep(for: .milliseconds(500))
        } while ContinuousClock.now < deadline

        if try await signInFormIsVisible() {
            throw Failure(status: .needsLogin, message: "BI Data 显示了公司登录表单，请重新登录后重试。")
        }
        guard matchesPortal(webView.url), !webView.isLoading else {
            throw Failure(status: .connectionFailed, message: "BI Data 页面未能加载完成，请检查网络连接后重试。")
        }
        throw Failure(status: .failed, message: "未能打开「渠道投放分析」或报表控件尚未加载。请重试此任务。")
    }

    private func signInFormIsVisible() async throws -> Bool {
        guard webView.url != nil, !webView.isLoading else { return false }
        // The portal can redirect to a separate sign-in origin. Only check whether a password field is visible.
        return try await webView.callAsyncJavaScript(
            """
            return Array.from(document.querySelectorAll('input[type="password"]')).some(field =>
                field.getClientRects().length && getComputedStyle(field).visibility === "visible");
            """,
            arguments: [:],
            in: nil,
            contentWorld: .defaultClient
        ) as? Bool == true
    }

    private func matchesPortal(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.host?.lowercased() == portal.host?.lowercased()
            && url.scheme == portal.scheme
            && (url.port ?? defaultPort(url)) == (portal.port ?? defaultPort(portal))
    }

    private func defaultPort(_ url: URL) -> Int { url.scheme == "https" ? 443 : 80 }

    private static let reportScript = Bundle.main.url(forResource: "bi_report", withExtension: "js")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }

    private func evaluate(_ operation: String, arguments: [String: Any] = [:]) async throws -> Any? {
        guard let script = Self.reportScript else {
            throw Failure(status: .failed, message: "应用缺少 BI Data 报表脚本。")
        }
        guard matchesPortal(webView.url) else {
            throw Failure(status: .connectionFailed, message: "BI Data 已离开配置的报表地址，请重试。")
        }
        // Check the origin in JavaScript too, in case navigation occurred while the call was queued.
        let origin = "\(portal.scheme ?? "")://\(portal.host ?? "")"
            + (portal.port.flatMap { $0 == defaultPort(portal) ? nil : ":\($0)" } ?? "")
        let result = try await webView.callAsyncJavaScript(
            "if (location.origin !== origin) return null;\n" + script,
            arguments: ["operation": operation, "args": arguments, "origin": origin],
            in: nil,
            contentWorld: .defaultClient
        )
        guard let result, !(result is NSNull) else {
            throw Failure(status: .connectionFailed, message: "BI Data 页面在操作期间发生跳转，请重试。")
        }
        return result
    }

    private func downloadReport(
        to output: URL, for run: BIDownloadRun, start: () async throws -> Void
    ) async throws {
        let partial = output.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).part")
        destination = partial
        downloadResult = nil
        defer {
            destination = nil
            download = nil
            try? FileManager.default.removeItem(at: partial)
        }

        do {
            try await start()
            try Task.checkCancellation()
            let deadline = ContinuousClock.now + .seconds(90)
            while downloadResult == nil && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(200))
            }
            guard let downloadResult else {
                throw Failure(status: .failed, message: "报表下载超时，可以从任务记录重试。")
            }
            try downloadResult.get()
            if run.reportKind == .productSales {
                _ = try ImportTextEncoding.normalizeToUTF8IfNeeded(at: partial)
            }
            try Self.validateReport(at: partial, for: run)
            try FileManager.default.moveItem(at: partial, to: output)
        } catch {
            _ = await download?.cancel()
            throw error
        }
    }

    private func trackDownload(_ download: WKDownload) {
        download.delegate = self
        self.download = download
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        if destination != nil, action.shouldPerformDownload, action.request.url?.scheme == "blob" {
            return .download
        }
        return .allow
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        trackDownload(download)
    }

    private static func validateReport(at url: URL, for run: BIDownloadRun) throws {
        switch run.reportKind {
        case .channelAnalysis:
            try validateCSV(at: url, dimensions: run.filters.dimensions)
        case .productSales:
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let prefix = try handle.read(upToCount: 65_536) ?? Data()
            let header = String(decoding: prefix.prefix { $0 != 10 && $0 != 13 }, as: UTF8.self)
            let separator = try DelimitedFileSniffer.detectSeparator(fileURL: url)
            _ = try SalesColumnMap(headers: TSVFieldParser.parseFields(header, delimiter: separator.rawValue))
        case .productDetail:
            let manifest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: manifest) }
            do {
                try ZipEntryExtractor.extractEntry(named: "xl/workbook.xml", from: url, to: manifest)
            } catch {
                throw Failure(status: .failed, message: "BI Data 未返回有效的投放产品明细 XLSX。")
            }
        }
    }

    static func validateCSV(at url: URL, dimensions: Set<BIDimension>) throws {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let sample = try file.read(upToCount: 65_536) ?? Data()
        guard let lineEnd = sample.firstIndex(where: { $0 == 10 || $0 == 13 }) else {
            throw Failure(status: .failed, message: "BI Data 返回的 CSV 没有数据行。")
        }
        let header = Data(sample[..<lineEnd])
        let decoded = String(data: header, encoding: .utf8) ?? String(data: header, encoding: ImportTextEncoding.gb18030)
        let columns = Set((decoded ?? "").split(separator: ",").map {
            ImportTextEncoding.normalizeHeaderField(String($0)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        })
        let required = Set(["Cost", "SALES_TOTAL"] + dimensions.map(\.rawValue))
        guard required.isSubset(of: columns), sample[lineEnd...].contains(where: { ![9, 10, 13, 32].contains($0) }) else {
            throw Failure(status: .failed, message: "CSV 表头或数据行与本次 BI Data 报表不符。")
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String
    ) async -> URL? {
        destination
    }

    func downloadDidFinish(_ download: WKDownload) { downloadResult = .success(()) }

    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        downloadResult = .failure(Failure(status: .failed, message: "无法下载 BI Data 报表，可以从任务记录重试。"))
    }
}
