import Foundation
import WebKit

enum BrowserAddress {
    static func parse(_ input: String, inferHTTPS: Bool = false) throws -> URL {
        var address = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if inferHTTPS && !address.contains("://") {
            let hasPort = address.range(
                of: #"^(?:\[[^\]]+\]|[^/:]+):[0-9]+(?:[/?#]|$)"#,
                options: .regularExpression
            ) != nil
            guard URLComponents(string: address)?.scheme == nil || hasPort else {
                throw URLError(.badURL)
            }
            address = "https://\(address)"
        }
        guard let components = URLComponents(string: address),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              !host.contains(where: \.isWhitespace),
              let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }
}

enum SettingsChanges {
    static func indices(from old: [String], to new: [String]) -> [Int] {
        precondition(old.count == new.count)
        return old.indices.filter { old[$0] != new[$0] }
    }
}

enum NavigationFailure {
    static func shouldReport(_ error: Error) -> Bool {
        let error = error as NSError
        return !(error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
            // WebKit reports download conversion using its legacy policy-error domain.
            && !(error.domain == "WebKitErrorDomain" && error.code == 102)
    }

    static func failingURL(_ error: Error) -> URL? {
        let info = (error as NSError).userInfo
        if let url = info[NSURLErrorFailingURLErrorKey] as? URL {
            return url
        }
        return (info[NSURLErrorFailingURLStringErrorKey] as? String).flatMap(URL.init(string:))
    }
}

enum AppResources {
    static var directory: URL? {
        #if SWIFT_PACKAGE
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
        #else
        Bundle.main.resourceURL
        #endif
    }

    static func script(named name: String) throws -> String {
        guard let directory else { throw CocoaError(.fileReadNoSuchFile) }
        return try String(contentsOf: directory.appendingPathComponent("\(name).js"), encoding: .utf8)
    }
}
