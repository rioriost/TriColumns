import XCTest
import WebKit
@testable import TriColumns

final class BrowserPolicyTests: XCTestCase {
    func testRejectsEmptyHostsAndUnsupportedSchemes() {
        for value in ["", "http://", "https://", "https:///path", "file:///tmp/page", "javascript:alert(1)", "https://bad host/"] {
            XCTAssertThrowsError(try BrowserAddress.parse(value), value)
        }
        for value in ["http:/example.com", "https:/example.com", "mailto:user@example.com"] {
            XCTAssertThrowsError(try BrowserAddress.parse(value, inferHTTPS: true), value)
        }
    }

    func testAcceptsBrowserAddressesWithoutLosingComponents() throws {
        for value in ["http://example.com/", "https://example.com:8443/path?q=test#part",
                      "https://[::1]:8443/", "https://例え.jp/検索?q=日本語"] {
            let url = try BrowserAddress.parse(value)
            XCTAssertNotNil(url.host)
            XCTAssertFalse(url.host!.isEmpty)
        }
        XCTAssertEqual(try BrowserAddress.parse(" example.com/path ", inferHTTPS: true).absoluteString,
                       "https://example.com/path")
        XCTAssertEqual(try BrowserAddress.parse("localhost:8080/path", inferHTTPS: true).absoluteString,
                       "https://localhost:8080/path")
        XCTAssertEqual(try BrowserAddress.parse("[::1]:8080/", inferHTTPS: true).port, 8080)
    }

    func testSettingsChangesOnlyIncludeChangedColumns() {
        let old = ["", "https://x.com/notifications", "https://x.com/home"]
        XCTAssertEqual(SettingsChanges.indices(from: old, to: old), [])
        XCTAssertEqual(SettingsChanges.indices(from: old, to: ["https://example.com", old[1], old[2]]), [0])
        XCTAssertEqual(SettingsChanges.indices(from: old, to: ["", "", ""]), [1, 2])
    }

    func testNavigationFailuresExcludeOnlyExpectedInterruptions() {
        XCTAssertFalse(NavigationFailure.shouldReport(URLError(.cancelled)))
        XCTAssertFalse(NavigationFailure.shouldReport(NSError(domain: "WebKitErrorDomain", code: 102)))
        for code in [URLError.cannotFindHost, .notConnectedToInternet, .secureConnectionFailed, .appTransportSecurityRequiresSecureConnection] {
            XCTAssertTrue(NavigationFailure.shouldReport(URLError(code)))
        }
        XCTAssertTrue(NavigationFailure.shouldReport(NSError(domain: WKError.errorDomain, code: 102)))
        let url = URL(string: "https://unreachable.invalid/path")!
        let error = NSError(domain: NSURLErrorDomain, code: -1003,
                            userInfo: [NSURLErrorFailingURLErrorKey: url])
        XCTAssertEqual(NavigationFailure.failingURL(error), url)
    }
}
