import AppKit
import WebKit
import XCTest
@testable import TriColumns

@MainActor
final class DownloadIntegrationTests: XCTestCase {
    @MainActor
    private final class Fixture: NSObject, WKNavigationDelegate {
        var origins: [WKWebView] = []
        var pending: [(NSApplication.ModalResponse) -> Void] = []
        var errors: [Error] = []
        lazy var coordinator = DownloadCoordinator(
            presentPanel: { [weak self] _, origin, completion in
                self?.origins.append(origin)
                self?.pending.append(completion)
            },
            reportError: { [weak self] error, _ in self?.errors.append(error) }
        )

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            decisionHandler(action.shouldPerformDownload ? .download : .allow)
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            coordinator.start(download, from: webView)
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw NSError(domain: "DownloadIntegrationTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for a WebKit download"])
    }

    private func makeView(delegate: Fixture) -> WKWebView {
        _ = NSApplication.shared
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = delegate
        view.loadHTMLString("<a id='download' download='fixture.txt' href='data:text/plain,fixture'>Download</a>",
                            baseURL: URL(string: "https://fixture.invalid"))
        return view
    }

    func testConcurrentDownloadsPreserveTheirOriginAndCancelWithoutErrors() async throws {
        let fixture = Fixture()
        let first = makeView(delegate: fixture)
        let second = makeView(delegate: fixture)
        defer {
            fixture.coordinator.cancelDownloads(from: first)
            fixture.coordinator.cancelDownloads(from: second)
            first.stopLoading()
            second.stopLoading()
        }
        try await waitUntil { !first.isLoading && !second.isLoading }
        _ = try await first.evaluateJavaScript("document.getElementById('download').click(); void 0")
        _ = try await second.evaluateJavaScript("document.getElementById('download').click(); void 0")
        try await waitUntil { fixture.origins.count == 2 }
        XCTAssertTrue(fixture.origins.contains { $0 === first })
        XCTAssertTrue(fixture.origins.contains { $0 === second })
        for completion in fixture.pending { completion(.cancel) }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(fixture.errors.isEmpty)
    }

    func testOriginClosingWhileSaveDecisionIsPendingToleratesLatePanelCallback() async throws {
        let fixture = Fixture()
        let view = makeView(delegate: fixture)
        defer {
            fixture.coordinator.cancelDownloads(from: view)
            view.stopLoading()
        }
        try await waitUntil { !view.isLoading }
        _ = try await view.evaluateJavaScript("document.getElementById('download').click(); void 0")
        try await waitUntil { fixture.pending.count == 1 }
        fixture.coordinator.cancelDownloads(from: view)
        fixture.pending[0](.cancel)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(fixture.errors.isEmpty)
    }
}
