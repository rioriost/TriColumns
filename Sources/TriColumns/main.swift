import AppKit
import WebKit

private struct ColumnSpec {
    let title: String
    let address: String
}

private enum L10n {
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

private let autoReloadInterval: TimeInterval? = {
    let defaultInterval: TimeInterval = 30 * 60
    guard let rawValue = ProcessInfo.processInfo.environment["TRICOLUMNS_RELOAD_SECONDS"] else {
        return defaultInterval
    }

    guard let value = TimeInterval(rawValue), value > 0 else {
        return nil
    }

    return max(value, 30)
}()

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
private final class BrowserColumnView: NSView, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, NSTextFieldDelegate {
    private let titleLabel = NSTextField(labelWithString: "")
    private let addressField = NSTextField(string: "")
    private let backButton = NSButton(title: "‹", target: nil, action: nil)
    private let forwardButton = NSButton(title: "›", target: nil, action: nil)
    private let reloadButton = NSButton(title: "↻", target: nil, action: nil)
    private let webView: WKWebView
    private var autoReloadTimer: Timer?
    private var popupControllers: [PopupWindowController] = []
    private var configuredAddress: String

    private static let reloadSafetyScript = """
        (() => {
          const visible = element => {
            if (!element) return false;
            const style = window.getComputedStyle(element);
            return style.display !== 'none' && style.visibility !== 'hidden';
          };
          const text = element => (element.innerText || element.value || '').trim();
          const hasDraft = Array.from(document.querySelectorAll(
            '[data-testid^="tweetTextarea_"], textarea'
          )).some(element => visible(element) && text(element).length > 0);
          const hasFiles = Array.from(document.querySelectorAll('input[type="file"]'))
            .some(element => element.files && element.files.length > 0);
          const active = document.activeElement;
          const isEditing = active && visible(active) && (
            active.isContentEditable ||
            active.matches('textarea, input:not([type="button"]):not([type="submit"]), select')
          );
          const hasModal = Array.from(document.querySelectorAll('[role="dialog"]'))
            .some(visible);
          const isPlaying = Array.from(document.querySelectorAll('audio, video'))
            .some(element => !element.paused && !element.ended);
          return hasDraft || hasFiles || isEditing || hasModal || isPlaying;
        })();
        """

    init(spec: ColumnSpec, configuration: WKWebViewConfiguration) {
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.configuredAddress = spec.address
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        titleLabel.stringValue = spec.title
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        addressField.stringValue = spec.address
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

        configure(webView)

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

        loadConfiguredAddress(spec.address)
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
        if webView === self.webView {
            if configuredAddress.isEmpty && webView.url?.absoluteString == "about:blank" {
                addressField.stringValue = ""
            } else {
                addressField.stringValue = webView.url?.absoluteString ?? addressField.stringValue
            }
            updateNavigationButtons()
        } else if let title = webView.title, !title.isEmpty {
            webView.window?.title = title
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if webView === self.webView {
            updateNavigationButtons()
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if webView === self.webView {
            updateNavigationButtons()
        }
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

        let webSchemes = ["http", "https", "file", "about", "blob", "data"]
        guard let scheme = url.scheme?.lowercased(), webSchemes.contains(scheme) else {
            if navigationAction.navigationType == .linkActivated {
                NSWorkspace.shared.open(url)
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
        download.delegate = self
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        download.delegate = self
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFilename
        panel.canCreateDirectories = true

        present(panel, for: webView) { [weak self] result in
            guard result == .OK, let destination = panel.url else {
                completionHandler(nil)
                return
            }

            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                completionHandler(destination)
            } catch {
                self?.showDownloadError(error)
                completionHandler(nil)
            }
        }
    }

    func download(
        _ download: WKDownload,
        didFailWithError error: Error,
        resumeData: Data?
    ) {
        showDownloadError(error)
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
            self?.popupControllers.removeAll { $0 === closedController }
        }
        popupControllers.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        return popupWebView
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
        alert.addButton(withTitle: "OK")
        present(alert, for: webView) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @Sendable (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = webView.title ?? "Web Page"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
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
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        present(alert, for: webView) { response in
            completionHandler(response == .alertFirstButtonReturn ? field.stringValue : nil)
        }
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        let host = origin.host.lowercased()
        let isTrustedHost = host == "x.com" || host.hasSuffix(".x.com") ||
            host == "twitter.com" || host.hasSuffix(".twitter.com")
        decisionHandler(origin.protocol == "https" && isTrustedHost ? .prompt : .deny)
    }

    @objc private func goBack() {
        webView.goBack()
    }

    @objc private func goForward() {
        webView.goForward()
    }

    @objc private func reload() {
        if configuredAddress.isEmpty {
            loadConfiguredAddress("")
        } else {
            webView.reload()
        }
    }

    @objc private func autoReload() {
        guard !webView.isLoading else {
            return
        }

        webView.evaluateJavaScript(Self.reloadSafetyScript) { [weak self] result, error in
            guard let self, error == nil, result as? Bool == false, !self.webView.isLoading else {
                return
            }
            self.webView.reload()
        }
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

        configuredAddress = url.absoluteString
        webView.load(URLRequest(url: url))
    }

    func loadConfiguredAddress(_ address: String) {
        configuredAddress = address
        addressField.stringValue = address

        guard !address.isEmpty, let url = URL(string: address) else {
            webView.load(URLRequest(url: URL(string: "about:blank")!))
            return
        }
        webView.load(URLRequest(url: url))
    }

    private func updateNavigationButtons() {
        backButton.isEnabled = webView.canGoBack
        forwardButton.isEnabled = webView.canGoForward
    }

    private func configure(_ webView: WKWebView) {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
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
        guard let window = webView.window else {
            completion(panel.runModal())
            return
        }
        panel.beginSheetModal(for: window, completionHandler: completion)
    }

    private func present(
        _ alert: NSAlert,
        for webView: WKWebView,
        completion: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        guard let window = webView.window else {
            completion(alert.runModal())
            return
        }
        alert.beginSheetModal(for: window, completionHandler: completion)
    }

    private func showDownloadError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = L10n.string("download.failed")
        present(alert, for: webView) { _ in }
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

@MainActor
private final class SettingsWindowController: NSWindowController {
    private let addressFields = (0..<3).map { _ in NSTextField(string: "") }
    private let onSave: ([String]) -> Void

    init(addresses: [String], onSave: @escaping ([String]) -> Void) {
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 210),
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
            field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            return [label, field]
        }

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 460
        grid.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = NSButton(
            title: L10n.string("button.cancel"),
            target: self,
            action: #selector(cancel)
        )
        cancelButton.keyEquivalent = "\u{1b}"

        let saveButton = NSButton(
            title: L10n.string("button.save"),
            target: self,
            action: #selector(save)
        )
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded

        let buttons = NSStackView(views: [cancelButton, saveButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(grid)
        contentView.addSubview(buttons)
        window.contentView = contentView

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            grid.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            buttons.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 24),
            buttons.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            buttons.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])

        update(addresses: addresses)
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(addresses: [String]) {
        for (field, address) in zip(addressFields, addresses) {
            field.stringValue = address
        }
    }

    @objc private func cancel() {
        window?.close()
    }

    @objc private func save() {
        let addresses = addressFields.map {
            $0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for (index, address) in addresses.enumerated() where !address.isEmpty {
            guard let components = URLComponents(string: address),
                  let scheme = components.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  components.host != nil else {
                showInvalidURLAlert(column: index + 1)
                return
            }
        }

        onSave(addresses)
        window?.close()
    }

    private func showInvalidURLAlert(column: Int) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.string("settings.invalid_url.title")
        alert.informativeText = L10n.format("settings.invalid_url.message", column)
        alert.addButton(withTitle: L10n.string("button.ok"))
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
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
        let specs = ColumnPreferences.addresses.enumerated().map { index, address in
            ColumnSpec(title: L10n.format("column.title", index + 1), address: address)
        }
        for spec in specs {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = dataStore
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true

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
        window.contentView = columnStack
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc private func showSettings(_ sender: Any?) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(addresses: ColumnPreferences.addresses) {
                [weak self] addresses in
                ColumnPreferences.save(addresses)
                for (column, address) in zip(self?.columns ?? [], addresses) {
                    column.loadConfiguredAddress(address)
                }
            }
        } else {
            settingsWindowController?.update(addresses: ColumnPreferences.addresses)
        }

        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.center()
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
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

        NSApp.mainMenu = mainMenu
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
