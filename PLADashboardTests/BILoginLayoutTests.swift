import Foundation
import Testing
import WebKit
@testable import PLADashboard

@MainActor
struct BILoginLayoutTests {
    @Test func welcomePageAuthenticatesBeforeOpeningReport() async throws {
        let portal = try #require(URL(string: "https://example.test"))
        let session = BIWebSession(portal: portal, accountID: UUID())
        let webView = session.webView
        webView.loadHTMLString("""
            <!doctype html>
            <style>@media (max-width: 900px) { main { display: none; } }</style>
            <main>
                <h1>Welcome</h1>
                <button>退出</button>
                <input type="password">
                <a hidden href="#">渠道投放分析</a>
                <iframe title="Welcome" srcdoc="
                    <h2>常用报表</h2>
                    <button onclick='parent.openReport()'>渠道投放分析</button>
                    <h2>最近访问</h2>
                    <button onclick='parent.openReport()'>渠道投放分析</button>
                "></iframe>
            </main>
            <script>
                function openReport() {
                    const report = document.createElement("iframe");
                    report.id = "report";
                    report.src = new URL("/ChannelReleaseEffect?from=welcome", location.href).href;
                    report.srcdoc = "<button>查询</button>";
                    document.body.append(report);
                }
            </script>
            """, baseURL: portal)

        for _ in 0..<40 {
            if !webView.isLoading,
               (try? await webView.evaluateJavaScript("!!document.querySelector('input[type=password]')") as? Bool) == true {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(try await !session.isAuthenticated())
        _ = try await webView.evaluateJavaScript("document.querySelector('input[type=password]').remove()")
        #expect(try await session.isAuthenticated())
        let openedBeforeExport = try await webView.evaluateJavaScript("!!document.querySelector('#report')")
        #expect(openedBeforeExport as? Bool == false)

        try await session.waitForReport(timeout: .seconds(5))
        let openedForOptions = try await webView.evaluateJavaScript("document.querySelectorAll('#report').length")
        #expect(openedForOptions as? Int == 1)
    }

    @Test(arguments: [false, true])
    func missingReportRequiresLoginOnlyWhenSignInIsVisible(hasSignInForm: Bool) async throws {
        let portal = try #require(URL(string: "https://example.test"))
        let session = BIWebSession(portal: portal, accountID: UUID())
        let webView = session.webView
        let passwordField = hasSignInForm ? "<input type='password'>" : "<input type='password' hidden>"
        webView.loadHTMLString("<main id='page'>\(passwordField)</main>", baseURL: portal)

        for _ in 0..<40 {
            if !webView.isLoading,
               (try? await webView.evaluateJavaScript("!!document.querySelector('#page')") as? Bool) == true {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        do {
            try await session.waitForReport(timeout: .zero)
            Issue.record("A page without a report must fail.")
        } catch let failure as BIWebSession.Failure {
            #expect(failure.status == (hasSignInForm ? .needsLogin : .failed))
        }
    }

    @Test func loginCanReachPasswordBelowTheViewport() async throws {
        let portal = try #require(URL(string: "https://example.test"))
        let session = BIWebSession(portal: portal, accountID: UUID(), allowsLoginLayout: true)
        let webView = session.webView
        webView.setFrameSize(CGSize(width: 800, height: 480))
        webView.loadHTMLString("""
            <!doctype html>
            <html style="overflow: hidden">
                <body style="height: 100vh; overflow: hidden">
                    <main style="padding-top: 800px">
                        <input type="password" aria-label="密码">
                        <button>登录</button>
                    </main>
                </body>
            </html>
            """, baseURL: nil)

        for _ in 0..<40 {
            if !webView.isLoading,
               (try? await webView.evaluateJavaScript("!!document.querySelector('input[type=password]')") as? Bool) == true {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        let overflow = try await webView.evaluateJavaScript("getComputedStyle(document.documentElement).overflowY")
        #expect(overflow as? String == "auto")
        let fitsAfterScroll = try await webView.evaluateJavaScript("""
            window.scrollTo(0, document.scrollingElement.scrollHeight);
            (() => {
                const field = document.querySelector('input[type=password]').getBoundingClientRect();
                return window.scrollY > 0 && field.top >= 0 && field.bottom <= window.innerHeight;
            })()
            """)
        #expect(fitsAfterScroll as? Bool == true)
    }
}
