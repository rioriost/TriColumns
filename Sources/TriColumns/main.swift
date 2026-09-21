import AppKit
import WebKit

struct ColumnSpec {
    let title: String
    let address: String
}

enum L10n {
    static func string(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: arguments)
    }
}

private enum ColumnPreferences {
    private static let keys = ["column1URL", "column2URL", "column3URL"]
    private static let defaults = [
        "",
        "https://x.com/notifications",
        "https://x.com/home"
    ]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: Dictionary(uniqueKeysWithValues: zip(keys, defaults)))
    }

    static var addresses: [String] {
        keys.map { UserDefaults.standard.string(forKey: $0) ?? "" }
    }

    static func save(_ addresses: [String]) {
        for (key, address) in zip(keys, addresses) {
            UserDefaults.standard.set(address, forKey: key)
        }
    }
}

private enum BrowserDefaults {
    static let autoReloadInterval: TimeInterval? = {
        let defaultInterval: TimeInterval = 30 * 60
        guard let rawValue = ProcessInfo.processInfo.environment["TRICOLUMNS_RELOAD_SECONDS"] else {
            return defaultInterval
        }
        guard let value = TimeInterval(rawValue), value > 0 else {
            return nil
        }
        return max(value, 30)
    }()

    static let sampleURLScheme = "tricolumns-sample"
}

private final class BundledSampleSchemeHandler: NSObject, WKURLSchemeHandler {
    private let resourceDirectory: URL

    init(resourceDirectory: URL) {
        self.resourceDirectory = resourceDirectory.standardizedFileURL
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        let relativePath = requestURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fileURL = resourceDirectory.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = resourceDirectory.path.hasSuffix("/")
            ? resourceDirectory.path
            : resourceDirectory.path + "/"

        guard fileURL.path.hasPrefix(rootPath),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let response = URLResponse(
                url: requestURL,
                mimeType: Self.mimeType(for: fileURL.pathExtension),
                expectedContentLength: data.count,
                textEncodingName: Self.isTextExtension(fileURL.pathExtension) ? "utf-8" : nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private static func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "html": return "text/html"
        case "css": return "text/css"
        case "js": return "application/javascript"
        case "png": return "image/png"
        default: return "application/octet-stream"
        }
    }

    private static func isTextExtension(_ pathExtension: String) -> Bool {
        ["html", "css", "js"].contains(pathExtension.lowercased())
    }
}

@MainActor
private final class PopupWindowController: NSWindowController, NSWindowDelegate {
    var onClose: ((PopupWindowController) -> Void)?

    init(webView: WKWebView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Web Page"
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        onClose?(self)
    }
}

@MainActor
final class BrowserColumnView: NSView, WKNavigationDelegate, WKUIDelegate, NSTextFieldDelegate {
    private let titleLabel = NSTextField(labelWithString: "")
    private let addressField = NSTextField(string: "")
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let reloadButton = NSButton()
    private let emptyState = NSStackView()
    let webView: WKWebView
    private let failureLabel = NSTextField(wrappingLabelWithString: "")
    private let failureBar = NSStackView()
    private(set) var failedURL: URL?
    private var autoReloadTimer: Timer?
    private var popupControllers: [PopupWindowController] = []
    private var configuredAddress: String
    private struct NavigationState {
        var navigation: WKNavigation?
        var generation = UUID()
    }
    private var navigationStates: [ObjectIdentifier: NavigationState] = [:]
    private var nativePanelCount = 0
    static let safetyWorld = WKContentWorld.world(name: "TriColumnsSafety")
    private lazy var downloads = DownloadCoordinator(
        presentPanel: { [weak self] panel, origin, completion in
            guard let self else { completion(.cancel); return }
            self.present(panel, for: origin, completion: completion)
        },
        reportError: { [weak self] error, origin in
            guard let self else { return }
            let alert = NSAlert(error: error)
            alert.messageText = L10n.string("download.failed")
            self.present(alert, for: origin ?? self.webView) { _ in }
        }
    )

    init(spec: ColumnSpec, configuration: WKWebViewConfiguration) {
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.configuredAddress = spec.address
        super.init(frame: .zero)

        wantsLayer = true

        titleLabel.stringValue = spec.title
        titleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        addressField.stringValue = spec.address
        addressField.font = .systemFont(ofSize: NSFont.systemFontSize)
        addressField.placeholderString = L10n.string("navigation.address.placeholder")
        addressField.setAccessibilityLabel(L10n.format("navigation.address.label", spec.title))
        addressField.setAccessibilityIdentifier("address-\(spec.title)")
        addressField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addressField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addressField.lineBreakMode = .byTruncatingMiddle
        addressField.delegate = self

        for (button, symbol, key) in [
            (backButton, "chevron.backward", "navigation.back"),
            (forwardButton, "chevron.forward", "navigation.forward"),
            (reloadButton, "arrow.clockwise", "navigation.reload")
        ] {
            let label = L10n.string(key)
            button.title = label
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            button.imagePosition = .imageOnly
            button.bezelStyle = .accessoryBarAction
            button.toolTip = label
            button.setAccessibilityLabel("\(spec.title): \(label)")
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 28),
                button.heightAnchor.constraint(equalToConstant: 28)
            ])
        }

        backButton.target = self
        backButton.action = #selector(goBack)
        forwardButton.target = self
        forwardButton.action = #selector(goForward)
        reloadButton.target = self
        reloadButton.action = #selector(reload)

        configure(webView)

        let toolbar = NSStackView(views: [backButton, forwardButton, addressField, reloadButton])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 6
        toolbar.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 8, right: 10)
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        let retryButton = NSButton(title: L10n.string("button.retry"), target: self, action: #selector(retryNavigation))
        retryButton.bezelStyle = .rounded
        failureLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        failureLabel.maximumNumberOfLines = 3
        failureLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        failureBar.orientation = .horizontal
        failureBar.spacing = 6
        failureBar.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        let failureIcon = NSImageView(image: NSImage(
            systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)!)
        failureIcon.contentTintColor = .secondaryLabelColor
        failureIcon.setAccessibilityHidden(true)
        failureBar.addArrangedSubview(failureIcon)
        failureBar.addArrangedSubview(failureLabel)
        failureBar.addArrangedSubview(retryButton)
        failureBar.isHidden = true
        let identity = NSStackView(views: [titleLabel])
        identity.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 4, right: 12)
        let divider = NSBox()
        divider.boxType = .separator
        let header = NSStackView(views: [identity, toolbar, failureBar, divider])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 0
        header.translatesAutoresizingMaskIntoConstraints = false

        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)
        addSubview(webView)

        let emptyIcon = NSImageView(image: NSImage(
            systemSymbolName: "globe", accessibilityDescription: nil)!)
        emptyIcon.contentTintColor = .secondaryLabelColor
        emptyIcon.imageScaling = .scaleProportionallyUpOrDown
        emptyIcon.setAccessibilityHidden(true)
        let emptyTitle = NSTextField(labelWithString: L10n.string("column.empty.title"))
        emptyTitle.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        let emptyHint = NSTextField(wrappingLabelWithString: L10n.string("column.empty.hint"))
        emptyHint.alignment = .center
        emptyHint.textColor = .secondaryLabelColor
        let openButton = NSButton(title: L10n.string("navigation.open_address"),
                                  target: self, action: #selector(focusAddress))
        openButton.bezelStyle = .rounded
        emptyState.orientation = .vertical
        emptyState.spacing = 12
        [emptyIcon, emptyTitle, emptyHint, openButton].forEach(emptyState.addArrangedSubview)
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        emptyState.isHidden = true
        addSubview(emptyState)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbar.widthAnchor.constraint(equalTo: header.widthAnchor),
            failureBar.widthAnchor.constraint(equalTo: header.widthAnchor),
            divider.widthAnchor.constraint(equalTo: header.widthAnchor),
            addressField.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
            emptyIcon.widthAnchor.constraint(equalToConstant: 32),
            emptyIcon.heightAnchor.constraint(equalToConstant: 32),
            emptyState.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: webView.centerYAnchor),
            emptyState.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
            emptyState.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -40),

            webView.topAnchor.constraint(equalTo: header.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        loadConfiguredAddress(spec.address)
        updateNavigationButtons()
        startAutoReloadTimer()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    @objc func focusAddress() {
        window?.makeFirstResponder(addressField)
        addressField.selectText(nil)
    }

    var containsKeyboardFocus: Bool {
        let responder = window?.firstResponder
        if let editor = responder as? NSTextView, editor.isFieldEditor,
           let field = editor.delegate as? NSView {
            return field.isDescendant(of: self)
        }
        return (responder as? NSView)?.isDescendant(of: self) == true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        let movement = notification.userInfo?["NSTextMovement"] as? Int
        guard movement == NSReturnTextMovement else {
            return
        }
        loadAddressField()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigationStates[ObjectIdentifier(webView)]?.navigation === navigation else { return }
        if webView === self.webView {
            if let sampleAddress = Self.sampleDisplayAddress(for: webView.url) {
                addressField.stringValue = sampleAddress
            } else if configuredAddress.isEmpty && webView.url?.absoluteString == "about:blank" {
                addressField.stringValue = ""
            } else {
                addressField.stringValue = webView.url?.absoluteString ?? addressField.stringValue
            }
            let isEmpty = webView.url?.absoluteString == "about:blank"
            emptyState.isHidden = !isEmpty
            webView.isHidden = isEmpty
            addressField.toolTip = webView.url?.scheme == "http" ? L10n.string("navigation.insecure") : nil
            addressField.textColor = webView.url?.scheme == "http" ? .systemOrange : .labelColor
            updateNavigationButtons()
        } else if let title = webView.title, !title.isEmpty {
            webView.window?.title = title
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        navigationStates[ObjectIdentifier(webView)] = NavigationState(navigation: navigation)
        if webView === self.webView {
            failureBar.isHidden = true
            emptyState.isHidden = true
            webView.isHidden = false
            failedURL = nil
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showNavigationFailure(error, navigation: navigation, in: webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showNavigationFailure(error, navigation: navigation, in: webView)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }

        let webSchemes = ["http", "https", "file", "about", "blob", "data", BrowserDefaults.sampleURLScheme]
        guard let scheme = url.scheme?.lowercased(), webSchemes.contains(scheme) else {
            if navigationAction.navigationType == .linkActivated {
                if !NSWorkspace.shared.open(url) {
                    let alert = NSAlert(error: URLError(.unsupportedURL))
                    alert.informativeText = url.absoluteString
                    present(alert, for: webView) { _ in }
                }
            }
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased()
        let isAttachment = disposition?.contains("attachment") == true
        decisionHandler(navigationResponse.canShowMIMEType && !isAttachment ? .allow : .download)
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        downloads.start(download, from: webView)
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        downloads.start(download, from: webView)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, isXURL(url) {
            webView.load(URLRequest(url: url))
            return nil
        }

        let popupWebView = WKWebView(frame: .zero, configuration: configuration)
        configure(popupWebView)
        let controller = PopupWindowController(webView: popupWebView)
        controller.onClose = { [weak self] closedController in
            if let closedView = closedController.window?.contentView as? WKWebView {
                self?.downloads.cancelDownloads(from: closedView)
                closedView.stopLoading()
                self?.navigationStates.removeValue(forKey: ObjectIdentifier(closedView))
                closedView.navigationDelegate = nil
                closedView.uiDelegate = nil
            }
            self?.popupControllers.removeAll { $0 === closedController }
        }
        popupControllers.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        return popupWebView
    }

    func webViewDidClose(_ webView: WKWebView) {
        popupControllers.first { $0.window?.contentView === webView }?.close()
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.resolvesAliases = true

        present(panel, for: webView) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = webView.title ?? "Web Page"
        alert.informativeText = message
        alert.addButton(withTitle: L10n.string("button.ok"))
        present(alert, for: webView) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = webView.title ?? "Web Page"
        alert.informativeText = message
        alert.addButton(withTitle: L10n.string("button.ok"))
        alert.addButton(withTitle: L10n.string("button.cancel"))
        present(alert, for: webView) { response in
            completionHandler(response == .alertFirstButtonReturn)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let field = NSTextField(string: defaultText ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 360, height: 24)

        let alert = NSAlert()
        alert.messageText = webView.title ?? "Web Page"
        alert.informativeText = prompt
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.string("button.ok"))
        alert.addButton(withTitle: L10n.string("button.cancel"))
        present(alert, for: webView) { response in
            completionHandler(response == .alertFirstButtonReturn ? field.stringValue : nil)
        }
    }

    @objc func goBack() {
        webView.goBack()
    }

    @objc func goForward() {
        webView.goForward()
    }

    @objc func reload() {
        if configuredAddress.isEmpty {
            loadConfiguredAddress("")
        } else {
            webView.reload()
        }
    }

    @objc private func autoReload() {
        guard !configuredAddress.isEmpty else { return }
        checkRefreshSafety { [weak self] safe in
            if safe { self?.webView.reload() }
        }
    }

    func checkRefreshSafety(completion: @escaping (Bool) -> Void) {
        guard !webView.isLoading, nativePanelCount == 0, window?.attachedSheet == nil else {
            completion(false)
            return
        }
        let generation = navigationStates[ObjectIdentifier(webView)]?.generation
        webView.evaluateJavaScript(
            "globalThis.__triColumnsRefreshSafety?.isUnsafe() ?? true",
            in: nil,
            in: Self.safetyWorld
        ) { [weak self] result in
            guard let self,
                  self.navigationStates[ObjectIdentifier(self.webView)]?.generation == generation,
                  !self.webView.isLoading, self.nativePanelCount == 0,
                  self.window?.attachedSheet == nil,
                  case .success(let value) = result, value as? Bool == false else {
                completion(false)
                return
            }
            completion(true)
        }
    }

    private func loadAddressField() {
        let rawValue = addressField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty else {
            return
        }

        do {
            let url = try BrowserAddress.parse(rawValue, inferHTTPS: true)
            configuredAddress = url.absoluteString
            load(url)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = L10n.string("settings.invalid_url.title")
            present(alert, for: webView) { _ in }
        }
    }

    func loadConfiguredAddress(_ address: String) {
        configuredAddress = address
        addressField.stringValue = address

        guard !address.isEmpty else {
            load(URL(string: "about:blank")!)
            return
        }
        do {
            load(try BrowserAddress.parse(address))
        } catch {
            failureLabel.stringValue = "\(L10n.string("settings.invalid_url.title")): \(address)"
            failureBar.isHidden = false
        }
    }

    func loadSamplePage(_ url: URL, displayAddress: String) {
        configuredAddress = displayAddress
        addressField.stringValue = displayAddress
        load(url)
    }

    private func load(_ url: URL) {
        let navigation = webView.load(URLRequest(url: url))
        navigationStates[ObjectIdentifier(webView)] = NavigationState(navigation: navigation)
    }

    @objc private func retryNavigation() {
        if let failedURL { load(failedURL) }
    }

    private func showNavigationFailure(_ error: Error, navigation: WKNavigation?, in origin: WKWebView) {
        guard NavigationFailure.shouldReport(error),
              let state = navigationStates[ObjectIdentifier(origin)],
              state.navigation === navigation else { return }
        let url = NavigationFailure.failingURL(error) ?? origin.url
        if origin === webView {
            failedURL = url
            failureLabel.stringValue = [
                L10n.string("navigation.failed"), url?.absoluteString, error.localizedDescription
            ].compactMap { $0 }.joined(separator: "\n")
            failureBar.isHidden = false
            addressField.stringValue = origin.url?.absoluteString ?? ""
            updateNavigationButtons()
        } else {
            let alert = NSAlert(error: error)
            alert.messageText = L10n.string("navigation.failed")
            alert.informativeText = [url?.absoluteString, error.localizedDescription].compactMap { $0 }.joined(separator: "\n")
            alert.addButton(withTitle: L10n.string("button.retry"))
            alert.addButton(withTitle: L10n.string("button.cancel"))
            present(alert, for: origin) { [weak self, weak origin] response in
                guard let self, let origin, response == .alertFirstButtonReturn, let url,
                      self.navigationStates[ObjectIdentifier(origin)]?.generation == state.generation else { return }
                origin.load(URLRequest(url: url))
            }
        }
    }

    private func updateNavigationButtons() {
        backButton.isEnabled = webView.canGoBack
        forwardButton.isEnabled = webView.canGoForward
    }

    private static func sampleDisplayAddress(for url: URL?) -> String? {
        guard let url,
              url.scheme == BrowserDefaults.sampleURLScheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let column = components.queryItems?.first(where: { $0.name == "column" })?.value else {
            return nil
        }

        return "tricolumns://sample/column-\(column)"
    }

    private func configure(_ webView: WKWebView) {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        navigationStates[ObjectIdentifier(webView)] = NavigationState()
    }

    private func isXURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else {
            return false
        }
        return host == "x.com" || host.hasSuffix(".x.com") ||
            host == "twitter.com" || host.hasSuffix(".twitter.com")
    }

    private func present(
        _ panel: NSSavePanel,
        for webView: WKWebView,
        completion: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        nativePanelCount += 1
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            self?.nativePanelCount -= 1
            completion(response)
        }
        guard let window = webView.window else {
            finish(panel.runModal())
            return
        }
        panel.beginSheetModal(for: window, completionHandler: finish)
    }

    private func present(
        _ alert: NSAlert,
        for webView: WKWebView,
        completion: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        nativePanelCount += 1
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            self?.nativePanelCount -= 1
            completion(response)
        }
        guard let window = webView.window else {
            finish(alert.runModal())
            return
        }
        alert.beginSheetModal(for: window, completionHandler: finish)
    }

    private func startAutoReloadTimer() {
        guard let interval = BrowserDefaults.autoReloadInterval else {
            return
        }

        autoReloadTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.autoReload() }
        }
    }

    func shutDown() {
        autoReloadTimer?.invalidate()
        autoReloadTimer = nil
        webView.stopLoading()
        downloads.cancelDownloads(from: webView)
        for controller in popupControllers { controller.close() }
        navigationStates.removeAll()
    }
}

@MainActor
private final class SettingsWindowController: NSWindowController {
    private let addressFields = (0..<3).map { _ in NSTextField(string: "") }
    private let onSave: ([String]) async -> Bool
    private var isSaving = false
    private var actionButtons: [NSButton] = []

    init(addresses: [String], onSave: @escaping ([String]) async -> Bool) {
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 310),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.string("settings.title")
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let rows = addressFields.enumerated().map { index, field -> [NSView] in
            let label = NSTextField(labelWithString: L10n.format("column.title", index + 1))
            label.alignment = .right
            field.placeholderString = "https://example.com/"
            field.font = .systemFont(ofSize: NSFont.systemFontSize)
            field.setAccessibilityLabel(L10n.format("navigation.address.label", label.stringValue))
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
            return [label, field]
        }

        let grid = NSGridView(views: rows)
        for index in addressFields.indices {
            grid.row(at: index).height = 28
            grid.row(at: index).yPlacement = .center
        }
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = NSButton(
            title: L10n.string("button.cancel"),
            target: self,
            action: #selector(cancel)
        )
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.bezelStyle = .rounded

        let saveButton = NSButton(
            title: L10n.string("button.save"),
            target: self,
            action: #selector(save)
        )
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded
        actionButtons = [saveButton, cancelButton]

        let buttons = NSStackView(views: [cancelButton, saveButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: L10n.string("settings.pages.title"))
        heading.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        let explanation = NSTextField(wrappingLabelWithString: L10n.string("settings.pages.hint"))
        explanation.textColor = .secondaryLabelColor
        let intro = NSStackView(views: [heading, explanation])
        intro.orientation = .vertical
        intro.alignment = .leading
        intro.spacing = 6
        intro.translatesAutoresizingMaskIntoConstraints = false
        let contentView = NSView()
        contentView.addSubview(intro)
        contentView.addSubview(grid)
        contentView.addSubview(buttons)
        window.contentView = contentView

        NSLayoutConstraint.activate([
            intro.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            intro.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            intro.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            explanation.widthAnchor.constraint(equalTo: intro.widthAnchor),
            grid.topAnchor.constraint(equalTo: intro.bottomAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            buttons.topAnchor.constraint(greaterThanOrEqualTo: grid.bottomAnchor, constant: 24),
            buttons.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            buttons.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])

        let keyViews: [NSView] = addressFields + [cancelButton, saveButton]
        for index in keyViews.indices {
            keyViews[index].nextKeyView = keyViews[(index + 1) % keyViews.count]
        }
        window.initialFirstResponder = addressFields.first
        update(addresses: addresses)
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(addresses: [String]) {
        guard !isSaving else { return }
        for (field, address) in zip(addressFields, addresses) {
            field.stringValue = address
        }
    }

    @objc private func cancel() {
        window?.close()
    }

    @objc private func save() {
        guard !isSaving else { return }
        let addresses = addressFields.map {
            $0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for (index, address) in addresses.enumerated() where !address.isEmpty {
            do {
                _ = try BrowserAddress.parse(address)
            } catch {
                showInvalidURLAlert(column: index + 1)
                return
            }
        }

        isSaving = true
        setControlsEnabled(false)
        Task { @MainActor in
            let saved = await onSave(addresses)
            isSaving = false
            setControlsEnabled(true)
            if saved { window?.close() }
        }
    }

    private func setControlsEnabled(_ enabled: Bool) {
        addressFields.forEach { $0.isEnabled = enabled }
        actionButtons.forEach { $0.isEnabled = enabled }
        window?.standardWindowButton(.closeButton)?.isEnabled = enabled
    }

    private func showInvalidURLAlert(column: Int) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.string("settings.invalid_url.title")
        alert.informativeText = L10n.format("settings.invalid_url.message", column)
        alert.addButton(withTitle: L10n.string("button.ok"))
        if let window {
            alert.beginSheetModal(for: window) { [weak self] _ in
                guard let self else { return }
                self.addressFields[column - 1].selectText(nil)
            }
        } else {
            alert.runModal()
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    private var window: NSWindow?
    private var columns: [BrowserColumnView] = []
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ColumnPreferences.registerDefaults()
        configureMainMenu()

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
        var userScripts: [WKUserScript] = []
        var resourceError: Error?
        do {
            let safety = try AppResources.script(named: "RefreshSafety")
            let pull = try AppResources.script(named: "XPullToRefresh")
            userScripts = [
                WKUserScript(source: safety, injectionTime: .atDocumentStart,
                             forMainFrameOnly: false, in: BrowserColumnView.safetyWorld),
                WKUserScript(source: pull, injectionTime: .atDocumentStart,
                             forMainFrameOnly: true, in: BrowserColumnView.safetyWorld)
            ]
        } catch {
            resourceError = error
        }
        let sampleDirectory = AppResources.directory?.appendingPathComponent(
            "ReviewDemo",
            isDirectory: true
        )
        let specs = ColumnPreferences.addresses.enumerated().map { index, address in
            ColumnSpec(title: L10n.format("column.title", index + 1), address: address)
        }
        for spec in specs {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = dataStore
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
            userScripts.forEach(configuration.userContentController.addUserScript)
            if let sampleDirectory {
                configuration.setURLSchemeHandler(
                    BundledSampleSchemeHandler(resourceDirectory: sampleDirectory),
                    forURLScheme: BrowserDefaults.sampleURLScheme
                )
            }

            let column = BrowserColumnView(spec: spec, configuration: configuration)
            column.translatesAutoresizingMaskIntoConstraints = false
            columnStack.addArrangedSubview(column)
            columns.append(column)
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
        window.title = "TriColumns"
        window.contentMinSize = NSSize(width: 960, height: 480)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = columnStack
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window

        if let resourceError {
            let alert = NSAlert(error: resourceError)
            alert.messageText = L10n.string("refresh.unavailable")
            alert.beginSheetModal(for: window)
        }

        if CommandLine.arguments.contains("--sample-workspace") {
            showSampleWorkspace(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func windowWillClose(_ notification: Notification) {
        columns.forEach { $0.shutDown() }
        settingsWindowController?.close()
    }

    @objc private func showSettings(_ sender: Any?) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(addresses: ColumnPreferences.addresses) {
                [weak self] addresses in
                guard let self else { return false }
                return await self.applySettings(addresses)
            }
        } else {
            settingsWindowController?.update(addresses: ColumnPreferences.addresses)
        }

        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.center()
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    private func applySettings(_ addresses: [String]) async -> Bool {
        let changed = SettingsChanges.indices(from: ColumnPreferences.addresses, to: addresses)
        var needsConfirmation = false
        for index in changed {
            let safe = await withCheckedContinuation { continuation in
                columns[index].checkRefreshSafety { continuation.resume(returning: $0) }
            }
            if !safe { needsConfirmation = true }
        }
        if needsConfirmation {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.string("settings.discard.title")
            alert.informativeText = L10n.string("settings.discard.message")
            alert.addButton(withTitle: L10n.string("button.cancel"))
            alert.addButton(withTitle: L10n.string("button.apply"))
            guard let settingsWindow = settingsWindowController?.window,
                  await alert.beginSheetModal(for: settingsWindow) == .alertSecondButtonReturn else {
                return false
            }
        }
        ColumnPreferences.save(addresses)
        for index in changed { columns[index].loadConfiguredAddress(addresses[index]) }
        return true
    }

    @objc private func showSampleWorkspace(_ sender: Any?) {
        guard let demoDirectory = AppResources.directory?.appendingPathComponent(
            "ReviewDemo",
            isDirectory: true
        ) else {
            showSampleWorkspaceError()
            return
        }

        let demoPage = demoDirectory.appendingPathComponent("demo.html")
        guard FileManager.default.fileExists(atPath: demoPage.path) else {
            showSampleWorkspaceError()
            return
        }

        let language = Locale.preferredLanguages.first?.hasPrefix("ja") == true ? "ja" : "en"
        for (index, column) in columns.enumerated() {
            var components = URLComponents()
            components.scheme = BrowserDefaults.sampleURLScheme
            components.host = "workspace"
            components.path = "/demo.html"
            components.queryItems = [
                URLQueryItem(name: "lang", value: language),
                URLQueryItem(name: "scenario", value: "workspace"),
                URLQueryItem(name: "column", value: String(index + 1))
            ]

            guard let pageURL = components.url else {
                showSampleWorkspaceError()
                return
            }

            column.loadSamplePage(
                pageURL,
                displayAddress: "tricolumns://sample/column-\(index + 1)"
            )
        }
    }

    @objc private func restoreConfiguredPages(_ sender: Any?) {
        for (column, address) in zip(columns, ColumnPreferences.addresses) {
            column.loadConfiguredAddress(address)
        }
    }

    private func showSampleWorkspaceError() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.string("sample.failed.title")
        alert.informativeText = L10n.string("sample.failed.message")
        alert.addButton(withTitle: L10n.string("button.ok"))

        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    @objc private func openPrivacyPolicy(_ sender: Any?) {
        let filename = Locale.preferredLanguages.first?.hasPrefix("ja") == true
            ? "PRIVACY_POLICY.md" : "PRIVACY_POLICY.en.md"
        guard let url = URL(string: "https://github.com/rioriost/TriColumns/blob/main/docs/\(filename)") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openSupport(_ sender: Any?) {
        guard let url = URL(string: "https://github.com/rioriost/TriColumns/issues") else { return }
        NSWorkspace.shared.open(url)
    }

    @MainActor
    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem(title: "TriColumns", action: nil, keyEquivalent: "")
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu(title: "TriColumns")

        let aboutItem = NSMenuItem(
            title: L10n.string("menu.about"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = NSApp
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: L10n.string("menu.settings"),
            action: #selector(showSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())

        let sampleItem = NSMenuItem(
            title: L10n.string("menu.open_sample"),
            action: #selector(showSampleWorkspace(_:)),
            keyEquivalent: "d"
        )
        sampleItem.keyEquivalentModifierMask = [.command, .shift]
        sampleItem.target = self
        appMenu.addItem(sampleItem)

        let restoreItem = NSMenuItem(
            title: L10n.string("menu.restore_configured"),
            action: #selector(restoreConfiguredPages(_:)),
            keyEquivalent: ""
        )
        restoreItem.target = self
        appMenu.addItem(restoreItem)
        appMenu.addItem(.separator())

        let privacyItem = NSMenuItem(
            title: L10n.string("menu.privacy"),
            action: #selector(openPrivacyPolicy(_:)),
            keyEquivalent: ""
        )
        privacyItem.target = self
        appMenu.addItem(privacyItem)

        let supportItem = NSMenuItem(
            title: L10n.string("menu.support"),
            action: #selector(openSupport(_:)),
            keyEquivalent: ""
        )
        supportItem.target = self
        appMenu.addItem(supportItem)
        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.string("menu.quit"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem(
            title: L10n.string("menu.edit"),
            action: nil,
            keyEquivalent: ""
        )
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: L10n.string("menu.edit"))
        addEditItem(L10n.string("menu.undo"), action: "undo:", key: "z", to: editMenu)
        addEditItem(
            L10n.string("menu.redo"),
            action: "redo:",
            key: "z",
            modifiers: [.command, .shift],
            to: editMenu
        )
        editMenu.addItem(.separator())
        addEditItem(L10n.string("menu.cut"), action: "cut:", key: "x", to: editMenu)
        addEditItem(L10n.string("menu.copy"), action: "copy:", key: "c", to: editMenu)
        addEditItem(L10n.string("menu.paste"), action: "paste:", key: "v", to: editMenu)
        addEditItem(L10n.string("menu.delete"), action: "delete:", key: "", to: editMenu)
        editMenu.addItem(.separator())
        addEditItem(L10n.string("menu.select_all"), action: "selectAll:", key: "a", to: editMenu)
        editMenuItem.submenu = editMenu

        let navigationMenu = NSMenu(title: L10n.string("menu.navigation"))
        let navigationItem = NSMenuItem(title: navigationMenu.title, action: nil, keyEquivalent: "")
        navigationItem.submenu = navigationMenu
        mainMenu.addItem(navigationItem)
        for (key, action, shortcut) in [
            ("navigation.back", #selector(navigateBack), "["),
            ("navigation.forward", #selector(navigateForward), "]"),
            ("navigation.reload", #selector(reloadColumn), "r"),
            ("navigation.open_address", #selector(focusCurrentAddress), "l")
        ] {
            let item = NSMenuItem(title: L10n.string(key), action: action, keyEquivalent: shortcut)
            item.target = self
            navigationMenu.addItem(item)
        }
        navigationMenu.addItem(.separator())
        for index in 0..<3 {
            let item = NSMenuItem(title: L10n.format("navigation.focus_column", index + 1),
                                  action: #selector(focusColumn(_:)), keyEquivalent: "\(index + 1)")
            item.tag = index
            item.target = self
            navigationMenu.addItem(item)
        }

        let windowMenu = NSMenu(title: L10n.string("menu.window"))
        let windowItem = NSMenuItem(title: windowMenu.title, action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        addEditItem(L10n.string("menu.minimize"), action: "performMiniaturize:", key: "m", to: windowMenu)
        addEditItem(L10n.string("menu.zoom"), action: "performZoom:", key: "", to: windowMenu)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = mainMenu
    }

    private var activeColumn: BrowserColumnView? {
        columns.first(where: \.containsKeyboardFocus) ?? columns.first
    }

    @objc private func focusColumn(_ sender: NSMenuItem) {
        guard columns.indices.contains(sender.tag) else { return }
        columns[sender.tag].focusAddress()
    }

    @objc private func focusCurrentAddress() { activeColumn?.focusAddress() }
    @objc private func navigateBack() { activeColumn?.goBack() }
    @objc private func navigateForward() { activeColumn?.goForward() }
    @objc private func reloadColumn() { activeColumn?.reload() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(navigateBack):
            return NSApp.keyWindow === window && activeColumn?.webView.canGoBack == true
        case #selector(navigateForward):
            return NSApp.keyWindow === window && activeColumn?.webView.canGoForward == true
        case #selector(reloadColumn), #selector(focusCurrentAddress), #selector(focusColumn(_:)):
            return NSApp.keyWindow === window && !columns.isEmpty
        default:
            return true
        }
    }

    private func addEditItem(
        _ title: String,
        action: String,
        key: String,
        modifiers: NSEvent.ModifierFlags = [.command],
        to menu: NSMenu
    ) {
        let item = NSMenuItem(
            title: title,
            action: Selector(action),
            keyEquivalent: key
        )
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.target = nil
        menu.addItem(item)
    }
}

private let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
