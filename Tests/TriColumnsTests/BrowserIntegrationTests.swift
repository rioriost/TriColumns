import AppKit
import WebKit
import XCTest
@testable import TriColumns

@MainActor
final class BrowserIntegrationTests: XCTestCase {
    private func makeColumn() throws -> BrowserColumnView {
        _ = NSApplication.shared
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.userContentController.addUserScript(WKUserScript(
            source: try AppResources.script(named: "RefreshSafety"),
            injectionTime: .atDocumentStart, forMainFrameOnly: false,
            in: BrowserColumnView.safetyWorld
        ))
        return BrowserColumnView(spec: ColumnSpec(title: "Test", address: ""), configuration: configuration)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw NSError(domain: "BrowserIntegrationTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for WebKit"])
    }

    private func isSafe(_ column: BrowserColumnView) async -> Bool {
        await withCheckedContinuation { continuation in
            column.checkRefreshSafety { continuation.resume(returning: $0) }
        }
    }

    func testColumnUsesIsolatedSafetyAndFailsClosedDuringNavigation() async throws {
        let column = try makeColumn()
        defer { column.shutDown() }
        try await waitUntil { !column.webView.isLoading }
        column.webView.loadHTMLString("<main>Reading</main>", baseURL: nil)
        let safeWhileLoading = await isSafe(column)
        XCTAssertFalse(safeWhileLoading)
        try await waitUntil { !column.webView.isLoading }
        let safeWhenLoaded = await isSafe(column)
        XCTAssertTrue(safeWhenLoaded)
        _ = try await column.webView.evaluateJavaScript("""
            document.body.innerHTML = '<input id="editor"><button id="other">Other</button>';
            editor.value = 'unsaved';
            editor.dispatchEvent(new Event('input', {bubbles: true}));
            other.focus();
            globalThis.__triColumnsRefreshSafety = { isUnsafe: () => false };
            void 0;
            """)
        let safeAfterEditing = await isSafe(column)
        XCTAssertFalse(safeAfterEditing)
    }

    func testFailuresAreScopedToCurrentNavigationAndRetainRetryURL() throws {
        let column = try makeColumn()
        defer { column.shutDown() }
        let oldNavigation = column.webView.loadHTMLString("old", baseURL: nil)
        column.webView(column.webView, didStartProvisionalNavigation: oldNavigation)
        let currentNavigation = column.webView.loadHTMLString("new", baseURL: nil)
        column.webView(column.webView, didStartProvisionalNavigation: currentNavigation)
        let url = URL(string: "https://unreachable.invalid/path")!
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost,
                            userInfo: [NSURLErrorFailingURLErrorKey: url])
        column.webView(column.webView, didFailProvisionalNavigation: oldNavigation, withError: error)
        XCTAssertNil(column.failedURL)
        column.webView(column.webView, didFailProvisionalNavigation: currentNavigation, withError: URLError(.cancelled))
        XCTAssertNil(column.failedURL)
        column.webView(column.webView, didFailProvisionalNavigation: currentNavigation, withError: error)
        XCTAssertEqual(column.failedURL, url)
        column.webView(column.webView, didStartProvisionalNavigation: nil)
        XCTAssertNil(column.failedURL)
    }

    func testSafetyResultCannotAuthorizeAReplacementDocument() async throws {
        let column = try makeColumn()
        defer { column.shutDown() }
        try await waitUntil { !column.webView.isLoading }
        let safe = await withCheckedContinuation { continuation in
            column.checkRefreshSafety { continuation.resume(returning: $0) }
            column.loadSamplePage(URL(string: "about:blank")!, displayAddress: "Test replacement")
        }
        XCTAssertFalse(safe)
    }

    func testNativeSheetSuppressesRefresh() async throws {
        let column = try makeColumn()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = column
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                             styleMask: [.titled], backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        defer {
            window.endSheet(sheet)
            sheet.orderOut(nil)
            column.shutDown()
            window.close()
        }
        try await waitUntil { !column.webView.isLoading }
        window.beginSheet(sheet, completionHandler: nil)
        XCTAssertNotNil(window.attachedSheet)
        let safe = await isSafe(column)
        XCTAssertFalse(safe)
    }

    func testWindowCloseClosesOnlyRequestedPopupAndShutdownClosesRemainingOnes() async throws {
        let column = try makeColumn()
        defer { column.shutDown() }
        try await waitUntil { !column.webView.isLoading }
        _ = try await column.webView.evaluateJavaScript("""
            window.firstChild = window.open('about:blank');
            window.secondChild = window.open('about:blank');
            void 0;
            """)
        func popupWindows() -> [NSWindow] {
            NSApp.windows.filter {
                guard let view = $0.contentView as? WKWebView else { return false }
                return view !== column.webView && view.uiDelegate === column
            }
        }
        try await waitUntil { popupWindows().count == 2 }
        let windows = popupWindows()
        _ = try await column.webView.evaluateJavaScript("firstChild.close(); void 0")
        try await waitUntil { popupWindows().count == 1 }
        XCTAssertEqual(windows.filter(\.isVisible).count, 1)
        XCTAssertTrue(column.webView.uiDelegate === column)
        column.webViewDidClose(column.webView)
        XCTAssertTrue(column.webView.uiDelegate === column)
        column.shutDown()
        XCTAssertTrue(popupWindows().isEmpty)
        XCTAssertTrue(windows.allSatisfy { !$0.isVisible })
    }
}
