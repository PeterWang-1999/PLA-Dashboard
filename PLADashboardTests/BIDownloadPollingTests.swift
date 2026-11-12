import Foundation
import Testing
import WebKit
@testable import PLADashboard

@MainActor
struct BIDownloadPollingTests {
    @Test(arguments: [1, 2, 3])
    func usesExactRemoteTaskAndEncodesDownloadPath(state: Int) async throws {
        let portal = try #require(URL(string: "https://example.test/ChannelReleaseEffect"))
        let session = BIWebSession(portal: portal, accountID: UUID())
        session.webView.loadHTMLString("<button>查询</button>", baseURL: portal)
        try await session.waitForReport(timeout: .seconds(5))

        let scriptURL = try #require(Bundle.main.url(forResource: "bi_report", withExtension: "js"))
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        let stub = """
        const fetch = async url => {
            if (url.pathname !== "/common2/look" ||
                url.searchParams.get("export_id") !== "" ||
                url.searchParams.get("exportname") !== "渠道投放分析") throw Error("Unexpected request");
            return {ok: true, redirected: false, json: async () => [
                {USER_DEFINED: "task-old", STATE: 2, PATH: "different.csv"},
                {USER_DEFINED: "task", STATE: state, PATH: "reports/A&B+C.csv"}
            ]};
        };
        """
        let result = try await session.webView.callAsyncJavaScript(
            stub + "\n" + script,
            arguments: ["operation": "checkDownload", "args": ["task": "task"], "state": state],
            in: nil,
            contentWorld: .defaultClient
        )
        let status = try #require(result as? [String: String])
        #expect(status["status"] == (state == 2 ? "ready" : "pending"))
        if state == 2 {
            let address = try #require(status["url"])
            let components = try #require(URLComponents(string: address))
            #expect(components.host == portal.host)
            #expect(components.path == "/common2/DownFile")
            #expect(components.queryItems == [URLQueryItem(name: "path", value: "reports/A&B+C.csv")])
        }
    }
}
