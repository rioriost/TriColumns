import AppKit
import WebKit

private struct ColumnSpec {
    let title: String
    let url: URL
}

private let defaultColumns: [ColumnSpec] = [
    ColumnSpec(title: "List", url: URL(string: "https://x.com/lists/94145057")!),
    ColumnSpec(title: "Notifications", url: URL(string: "https://x.com/notifications")!),
    ColumnSpec(title: "Home", url: URL(string: "https://x.com/home")!)
]

private let autoReloadInterval: TimeInterval? = {
    let defaultInterval: TimeInterval = 5 * 60
    guard let rawValue = ProcessInfo.processInfo.environment["PSEUDO_TWEETDECK_RELOAD_SECONDS"] else {
        return defaultInterval
    }

    guard let value = TimeInterval(rawValue), value > 0 else {
        return nil
    }

    return max(value, 30)
}()

private final class BrowserColumnView: NSView, WKNavigationDelegate, WKUIDelegate, NSTextFieldDelegate {
    private let titleLabel = NSTextField(labelWithString: "")
    private let addressField = NSTextField(string: "")
    private let backButton = NSButton(title: "‹", target: nil, action: nil)
    private let forwardButton = NSButton(title: "›", target: nil, action: nil)
    private let reloadButton = NSButton(title: "↻", target: nil, action: nil)
    private let webView: WKWebView
    private var autoReloadTimer: Timer?

    init(spec: ColumnSpec, configuration: WKWebViewConfiguration) {
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        titleLabel.stringValue = spec.title
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        addressField.stringValue = spec.url.absoluteString
        addressField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        addressField.lineBreakMode = .byTruncatingMiddle
        addressField.delegate = self

        for button in [backButton, forwardButton, reloadButton] {
            button.bezelStyle = .texturedRounded
            button.translatesAutoresizingMaskIntoConstraints = false
        }

        backButton.target = self
        backButton.action = #selector(goBack)
        forwardButton.target = self
        forwardButton.action = #selector(goForward)
        reloadButton.target = self
        reloadButton.action = #selector(reload)

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        if let customUserAgent = ProcessInfo.processInfo.environment["PSEUDO_TWEETDECK_USER_AGENT"],
           !customUserAgent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            webView.customUserAgent = customUserAgent
        }

        let toolbar = NSStackView(views: [backButton, forwardButton, reloadButton, titleLabel, addressField])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 6
        toolbar.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toolbar)
        addSubview(webView)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 38),

            titleLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 140),
            backButton.widthAnchor.constraint(equalToConstant: 30),
            forwardButton.widthAnchor.constraint(equalToConstant: 30),
            reloadButton.widthAnchor.constraint(equalToConstant: 30),

            webView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        webView.load(URLRequest(url: spec.url))
        updateNavigationButtons()
        startAutoReloadTimer()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        let movement = notification.userInfo?["NSTextMovement"] as? Int
        guard movement == NSReturnTextMovement else {
            return
        }
        loadAddressField()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        addressField.stringValue = webView.url?.absoluteString ?? addressField.stringValue
        updateNavigationButtons()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        updateNavigationButtons()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        updateNavigationButtons()
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    @objc private func goBack() {
        webView.goBack()
    }

    @objc private func goForward() {
        webView.goForward()
    }

    @objc private func reload() {
        webView.reload()
    }

    @objc private func autoReload() {
        guard !webView.isLoading else {
            return
        }
        webView.reload()
    }

    private func loadAddressField() {
        let rawValue = addressField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty else {
            return
        }

        let normalized = rawValue.contains("://") ? rawValue : "https://\(rawValue)"
        guard let url = URL(string: normalized) else {
            NSSound.beep()
            return
        }

        webView.load(URLRequest(url: url))
    }

    private func updateNavigationButtons() {
        backButton.isEnabled = webView.canGoBack
        forwardButton.isEnabled = webView.canGoForward
    }

    private func startAutoReloadTimer() {
        guard let interval = autoReloadInterval else {
            return
        }

        autoReloadTimer = Timer.scheduledTimer(
            timeInterval: interval,
            target: self,
            selector: #selector(autoReload),
            userInfo: nil,
            repeats: true
        )
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let columnStack = NSStackView()
        columnStack.orientation = .horizontal
        columnStack.alignment = .top
        columnStack.distribution = .fillEqually
        columnStack.spacing = 1
        columnStack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        columnStack.autoresizingMask = [.width, .height]
        columnStack.wantsLayer = true
        columnStack.layer?.backgroundColor = NSColor.separatorColor.cgColor

        let dataStore = WKWebsiteDataStore.default()
        for spec in defaultColumns {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = dataStore
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true

            let column = BrowserColumnView(spec: spec, configuration: configuration)
            column.translatesAutoresizingMaskIntoConstraints = false
            columnStack.addArrangedSubview(column)
        }

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1600, height: 1000)
        let windowFrame = NSRect(
            x: screenFrame.minX + 40,
            y: screenFrame.minY + 40,
            width: min(screenFrame.width - 80, 1800),
            height: min(screenFrame.height - 80, 1100)
        )

        let window = NSWindow(
            contentRect: windowFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PseudoTweetDeck"
        window.contentView = columnStack
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

private let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
