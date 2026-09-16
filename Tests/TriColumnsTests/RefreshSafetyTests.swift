import AppKit
import WebKit
import XCTest

@MainActor
final class RefreshSafetyTests: XCTestCase {
    func testEmptyDocumentAndIsolatedImmutableInterface() async throws {
        let browser = try RefreshSafetyBrowser()
        defer { browser.close() }
        try await browser.load("<main>Read-only timeline</main>")

        let unsafe = try await browser.isUnsafe()
        let documentID: String = try await browser.evaluate("__triColumnsRefreshSafety.documentID")
        let pageCannotSeeTracker: Bool = try await browser.evaluate(
            "typeof globalThis.__triColumnsRefreshSafety === 'undefined'", world: .page
        )
        let immutable: Bool = try await browser.evaluate("""
            Object.isFrozen(__triColumnsRefreshSafety) &&
            !Reflect.set(globalThis, '__triColumnsRefreshSafety', { isUnsafe: () => false }) &&
            !Reflect.deleteProperty(globalThis, '__triColumnsRefreshSafety')
            """)
        XCTAssertFalse(unsafe)
        XCTAssertEqual(documentID.count, 32)
        XCTAssertTrue(pageCannotSeeTracker)
        XCTAssertTrue(immutable)

        try await browser.run("""
            globalThis.__triColumnsRefreshSafety = { isUnsafe: () => false, documentID: 'fake' };
            document.body.innerHTML = '<textarea>Unsaved draft</textarea>';
            """, world: .page)
        let stillUnsafe = try await browser.isUnsafe()
        let unchangedID: String = try await browser.evaluate("__triColumnsRefreshSafety.documentID")
        XCTAssertTrue(stillUnsafe)
        XCTAssertEqual(unchangedID, documentID)
    }

    func testBlurredAndRestoredEditorsAreUnsafeWithoutInputEvents() async throws {
        let browser = try RefreshSafetyBrowser()
        defer { browser.close() }
        let drafts = [
            "<div contenteditable='true'><span>Draft</span></div>",
            "<div contenteditable='plaintext-only'>Draft</div>",
            "<textarea>Draft</textarea>",
            "<input type='text' value='Draft'>",
            "<input type='search' value='Draft'>",
            "<div data-testid='tweetTextarea_0'>X draft</div>"
        ]
        for draft in drafts {
            try await browser.load(draft)
            let unsafe = try await browser.isUnsafe()
            XCTAssertTrue(unsafe, draft)
        }
        try await browser.load("<input id='editor'>")
        try await browser.run("""
            const editor = document.getElementById('editor');
            editor.focus();
            editor.value = 'Restored without an input event';
            editor.blur();
            """, world: .page)
        let unsafe = try await browser.isUnsafe()
        XCTAssertTrue(unsafe)
    }

    func testFocusBlocksOnlyUntilBlurIfNothingWasEdited() async throws {
        let browser = try RefreshSafetyBrowser()
        defer { browser.close() }
        for control in [
            "<input id='editor'>", "<textarea id='editor'></textarea>",
            "<select id='editor'><option>First</option></select>",
            "<div id='editor' contenteditable='true'></div>"
        ] {
            try await browser.load(control)
            try await browser.run("document.getElementById('editor').focus();")
            let focused = try await browser.isUnsafe()
            try await browser.run("document.getElementById('editor').blur();")
            let blurred = try await browser.isUnsafe()
            XCTAssertTrue(focused, control)
            XCTAssertFalse(blurred, control)
        }
    }

    func testInputAndChangeAreStickyAfterBlurFormResetAndRemoval() async throws {
        let browser = try RefreshSafetyBrowser()
        defer { browser.close() }
        for eventType in ["input", "change"] {
            for control in [
                "<input id='editor'>", "<input id='editor' type='checkbox'>",
                "<textarea id='editor'></textarea>",
                "<select id='editor'><option>First</option><option>Second</option></select>",
                "<div id='editor' contenteditable='true'><span id='child'></span></div>"
            ] {
                try await browser.load("<form>\(control)</form>")
                try await browser.run("""
                    const editor = document.getElementById('editor');
                    editor.focus();
                    if (editor.isContentEditable) {
                      document.getElementById('child').textContent = 'Draft';
                    } else if (editor.type === 'checkbox') {
                      editor.checked = true;
                    } else {
                      editor.value = editor.tagName === 'SELECT' ? 'Second' : 'Draft';
                    }
                    (document.getElementById('child') || editor).dispatchEvent(
                      new Event('\(eventType)', { bubbles: true, composed: true })
                    );
                    editor.blur();
                    document.querySelector('form').reset();
                    editor.remove();
                    """, world: .page)
                let unsafe = try await browser.isUnsafe()
                XCTAssertTrue(unsafe, "\(eventType): \(control)")
            }
        }
    }

    func testEarlyPageEditIsRecordedBeforeDOMContentLoaded() async throws {
        let browser = try RefreshSafetyBrowser()
        defer { browser.close() }
        try await browser.load("""
            <input id='editor'>
            <script>
              const editor = document.getElementById('editor');
              editor.value = 'Draft';
              editor.dispatchEvent(new Event('input', { bubbles: true }));
              editor.value = '';
            </script>
            """)
        let unsafe = try await browser.isUnsafe()
        XCTAssertTrue(unsafe)
    }

    func testOnlyFreshDocumentResetsDirtyStateAndIdentity() async throws {
        let browser = try RefreshSafetyBrowser()
        defer { browser.close() }
        try await browser.load("<input id='editor'>")
        let firstID: String = try await browser.evaluate("__triColumnsRefreshSafety.documentID")
        try await browser.run("""
            document.getElementById('editor').dispatchEvent(
              new Event('input', { bubbles: true, composed: true })
            );
            history.replaceState({}, '', '#spa-route');
            """)
        try await browser.run(RefreshSafetyBrowser.resource("RefreshSafety"))
        let sameDocumentID: String = try await browser.evaluate("__triColumnsRefreshSafety.documentID")
        let dirty = try await browser.isUnsafe()
        XCTAssertEqual(firstID, sameDocumentID)
        XCTAssertTrue(dirty)

        try await browser.load("<main>Fresh document</main>")
        let secondID: String = try await browser.evaluate("__triColumnsRefreshSafety.documentID")
        let freshUnsafe = try await browser.isUnsafe()
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertFalse(freshUnsafe)
    }

    func testEveryFrameIsConservativelyUnsafeAndReceivesItsOwnTracker() async throws {
        let browser = try RefreshSafetyBrowser()
        defer { browser.close() }
        try await browser.load("<iframe srcdoc='<main>Empty child</main>'></iframe>")
        let unsafe = try await browser.isUnsafe()
        let differentFrameID: Bool = try await browser.evaluate("""
            document.querySelector('iframe').contentWindow.__triColumnsRefreshSafety.documentID !==
              __triColumnsRefreshSafety.documentID
            """)
        let childIsSafe: Bool = try await browser.evaluate("""
            document.querySelector('iframe').contentWindow.__triColumnsRefreshSafety.isUnsafe() === false
            """)
        XCTAssertTrue(unsafe)
        XCTAssertTrue(differentFrameID)
        XCTAssertTrue(childIsSafe)

        // Sandboxed srcdoc has an opaque, cross-origin identity without a network request.
        try await browser.load("<iframe sandbox='allow-scripts' srcdoc='<input value=Draft>'></iframe>")
        let opaqueFrameUnsafe = try await browser.isUnsafe()
        XCTAssertTrue(opaqueFrameUnsafe)

        try await browser.load("<frameset><frame src='about:blank'></frameset>")
        let legacyFrameUnsafe = try await browser.isUnsafe()
        XCTAssertTrue(legacyFrameUnsafe)
    }

    func testNativeAndARIADialogsBlockAwayFromTopOfViewport() async throws {
        let browser = try RefreshSafetyBrowser()
        defer { browser.close() }
        try await browser.load("<dialog style='position:fixed;top:450px'>Confirm</dialog>")
        let closed = try await browser.isUnsafe()
        XCTAssertFalse(closed)
        try await browser.run("document.querySelector('dialog').showModal();", world: .page)
        let modal = try await browser.isUnsafe()
        XCTAssertTrue(modal)
        try await browser.run("document.querySelector('dialog').close();", world: .page)
        let closedAgain = try await browser.isUnsafe()
        XCTAssertFalse(closedAgain)

        for dialog in [
            "<dialog open style='position:absolute;top:2000px'>Nonmodal</dialog>",
            "<dialog open style='display:none'>Open but hidden</dialog>",
            "<div role='dialog' style='position:absolute;top:2000px'>Confirm</div>",
            "<div role='alertdialog' style='position:fixed;bottom:0'>Warning</div>"
        ] {
            try await browser.load(dialog)
            let unsafe = try await browser.isUnsafe()
            XCTAssertTrue(unsafe, dialog)
        }
        try await browser.load("<div style='display:none'><div role='dialog'>Dormant</div></div>")
        let hiddenARIA = try await browser.isUnsafe()
        XCTAssertFalse(hiddenARIA)
    }

    func testOpenShadowRootsAreInspectedAndComposedEventsStayDirty() async throws {
        let browser = try RefreshSafetyBrowser()
        defer { browser.close() }
        for eventType in ["input", "change"] {
            try await browser.load("<div id='host'></div>")
            try await browser.run("""
                const root = document.getElementById('host').attachShadow({ mode: 'open' });
                root.innerHTML = '<input id="editor">';
                const editor = root.getElementById('editor');
                editor.value = 'Draft';
                editor.dispatchEvent(new Event('\(eventType)', { bubbles: true, composed: true }));
                editor.value = '';
                """, world: .page)
            let unsafe = try await browser.isUnsafe()
            XCTAssertTrue(unsafe, eventType)
        }
        try await browser.load("<div id='host'></div>")
        try await browser.run("""
            document.getElementById('host').attachShadow({ mode: 'open' }).innerHTML =
              '<input id="editor">';
            """, world: .page)
        let emptyRootUnsafe = try await browser.isUnsafe()
        XCTAssertFalse(emptyRootUnsafe)
        try await browser.run("""
            const editor = document.getElementById('host').shadowRoot.getElementById('editor');
            editor.dispatchEvent(new Event('change', { bubbles: true, composed: false }));
            """, world: .page)
        let noncomposedChangeUnsafe = try await browser.isUnsafe()
        XCTAssertTrue(noncomposedChangeUnsafe)

        for contents in [
            "<div contenteditable='true'>Shadow draft</div>",
            "<dialog open>Shadow dialog</dialog>",
            "<div role='dialog' style='position:fixed;top:500px'>Shadow dialog</div>",
            "<iframe srcdoc='Empty'></iframe>"
        ] {
            try await browser.load("<div id='host'></div>")
            let quotedContents = try RefreshSafetyBrowser.jsString(contents)
            try await browser.run("""
                const outer = document.getElementById('host').attachShadow({ mode: 'open' });
                outer.innerHTML = '<div id="nested"></div>';
                outer.getElementById('nested').attachShadow({ mode: 'open' }).innerHTML = \(quotedContents);
                """, world: .page)
            let unsafe = try await browser.isUnsafe()
            XCTAssertTrue(unsafe, contents)
        }
    }

    func testOpaqueCustomComponentsFailClosedButOrdinaryAndOpenHostsDoNot() async throws {
        let browser = try RefreshSafetyBrowser()
        defer { browser.close() }
        try await browser.load("<main><div data-testid='cellInnerDiv'>Normal X layout</div></main>")
        let ordinary = try await browser.isUnsafe()
        XCTAssertFalse(ordinary)

        try await browser.run("""
            customElements.define('private-editor', class extends HTMLElement {
              constructor() {
                super();
                this.attachShadow({ mode: 'closed' }).innerHTML = '<input value="Secret draft">';
              }
            });
            document.body.append(document.createElement('private-editor'));
            """, world: .page)
        let opaque = try await browser.isUnsafe()
        XCTAssertTrue(opaque)

        try await browser.load("<open-component></open-component>")
        try await browser.run("""
            document.querySelector('open-component').attachShadow({ mode: 'open' }).innerHTML =
              '<span>Read-only component</span>';
            """, world: .page)
        let open = try await browser.isUnsafe()
        XCTAssertFalse(open)
    }

    func testSelectedFilesWithoutEventsBlockInDocumentAndShadowRoot() async throws {
        let browser = try RefreshSafetyBrowser()
        defer { browser.close() }
        for shadow in [false, true] {
            try await browser.load("<div id='host'></div>")
            try await browser.run("""
                const host = document.getElementById('host');
                const root = \(shadow ? "host.attachShadow({ mode: 'open' })" : "host");
                root.innerHTML = '<input type="file">';
                const transfer = new DataTransfer();
                transfer.items.add(new File(['Unsaved attachment'], 'draft.txt', { type: 'text/plain' }));
                root.querySelector('input').files = transfer.files;
                """, world: .page)
            let unsafe = try await browser.isUnsafe()
            XCTAssertTrue(unsafe, "shadow: \(shadow)")
            try await browser.run("""
                const host = document.getElementById('host');
                (host.shadowRoot || host).querySelector('input').value = '';
                """, world: .page)
            let cleared = try await browser.isUnsafe()
            XCTAssertFalse(cleared)
        }
    }

    func testRealSilentMediaPlaybackBlocksEvenInsideShadowRoot() async throws {
        let browser = try RefreshSafetyBrowser()
        defer { browser.close() }
        try await browser.load("<div id='host'></div>")
        try await browser.run("""
            const root = document.getElementById('host').attachShadow({ mode: 'open' });
            root.innerHTML = '<audio muted loop></audio>';
            const audio = root.querySelector('audio');
            audio.muted = true;
            const buffer = new ArrayBuffer(16044);
            const view = new DataView(buffer);
            const text = (offset, value) => [...value].forEach(
              (character, index) => view.setUint8(offset + index, character.charCodeAt(0))
            );
            text(0, 'RIFF'); view.setUint32(4, 16036, true); text(8, 'WAVE');
            text(12, 'fmt '); view.setUint32(16, 16, true); view.setUint16(20, 1, true);
            view.setUint16(22, 1, true); view.setUint32(24, 8000, true);
            view.setUint32(28, 16000, true); view.setUint16(32, 2, true);
            view.setUint16(34, 16, true); text(36, 'data'); view.setUint32(40, 16000, true);
            audio.src = 'data:audio/wav;base64,' + btoa(String.fromCharCode(...new Uint8Array(buffer)));
            globalThis.__mediaError = '';
            audio.play().catch(error => globalThis.__mediaError = String(error));
            """, world: .page)
        let playing = try await browser.waitUntil("""
            !document.getElementById('host').shadowRoot.querySelector('audio').paused
            """)
        if !playing {
            let error: String = try await browser.evaluate("globalThis.__mediaError", world: .page)
            throw XCTSkip("This host cannot play local silent WAV audio: \(error)")
        }
        let unsafe = try await browser.isUnsafe()
        XCTAssertTrue(unsafe)
        try await browser.run("""
            document.getElementById('host').shadowRoot.querySelector('audio').pause();
            """, world: .page)
        let paused = try await browser.isUnsafe()
        XCTAssertFalse(paused)
    }

    func testWheelThresholdPassiveDispatchAndRealCooldown() async throws {
        let browser = try RefreshSafetyBrowser(pullToRefresh: true)
        defer { browser.close() }
        try await browser.loadTimeline()
        let belowThreshold = try await browser.wheel(-71)
        let threshold = try await browser.wheel(-1)
        let coolingDown = try await browser.wheel(-72)
        let defaultPrevented: Bool = try await browser.evaluate("__lastWheelDefaultPrevented")
        XCTAssertEqual(belowThreshold, 0)
        XCTAssertEqual(threshold, 1)
        XCTAssertEqual(coolingDown, 1)
        XCTAssertFalse(defaultPrevented)

        try await Task.sleep(for: .milliseconds(1_300))
        let afterCooldown = try await browser.wheel(-72)
        XCTAssertEqual(afterCooldown, 2)
    }

    func testWheelGestureResetsAfter500MillisecondsAndOnDownwardScroll() async throws {
        let browser = try RefreshSafetyBrowser(pullToRefresh: true)
        defer { browser.close() }
        try await browser.loadTimeline()
        let initial = try await browser.wheel(-40)
        try await Task.sleep(for: .milliseconds(600))
        let reset = try await browser.wheel(-32)
        let completed = try await browser.wheel(-40)
        XCTAssertEqual(initial, 0)
        XCTAssertEqual(reset, 0)
        XCTAssertEqual(completed, 1)

        try await browser.loadTimeline()
        _ = try await browser.wheel(-40)
        _ = try await browser.wheel(1)
        let reversed = try await browser.wheel(-32)
        let nextPull = try await browser.wheel(-40)
        XCTAssertEqual(reversed, 0)
        XCTAssertEqual(nextPull, 1)
    }

    func testWheelHostMainControlAndNestedScrollGates() async throws {
        let browser = try RefreshSafetyBrowser(pullToRefresh: true)
        defer { browser.close() }
        for host in ["example.com", "x.com.example.com"] {
            try await browser.loadTimeline(host: host)
            let clicks = try await browser.wheel(-72)
            XCTAssertEqual(clicks, 0, host)
        }
        try await browser.loadTimeline(host: "mobile.x.com")
        let controlWheel = try await browser.wheel(-72, options: "ctrlKey: true")
        let outsideMain = try await browser.wheel(-72, target: "#outside")
        XCTAssertEqual(controlWheel, 0)
        XCTAssertEqual(outsideMain, 0)
        try await browser.run("""
            document.querySelector('main').style.height = '2400px';
            scrollTo(0, 100);
            """)
        let rootScroll: Double = try await browser.evaluate("document.scrollingElement.scrollTop")
        XCTAssertGreaterThan(rootScroll, 2)
        let scrolled = try await browser.wheel(-72)
        XCTAssertEqual(scrolled, 0)
        try await browser.run("""
            scrollTo(0, 0);
            const nested = document.getElementById('nested');
            nested.scrollTop = 50;
            """)
        let nestedScrolled = try await browser.wheel(-72, target: "#nested-content")
        XCTAssertEqual(nestedScrolled, 0)
        try await browser.run("document.getElementById('nested').scrollTop = 0;")
        let atTop = try await browser.wheel(-72, target: "#nested-content")
        XCTAssertEqual(atTop, 1)
    }

    func testWheelNormalizesLineAndPageDeltas() async throws {
        let browser = try RefreshSafetyBrowser(pullToRefresh: true)
        defer { browser.close() }
        try await browser.loadTimeline()
        let below = try await browser.wheel(-4, options: "deltaMode: WheelEvent.DOM_DELTA_LINE")
        let enough = try await browser.wheel(-0.5, options: "deltaMode: WheelEvent.DOM_DELTA_LINE")
        XCTAssertEqual(below, 0)
        XCTAssertEqual(enough, 1)
        try await browser.loadTimeline()
        let page = try await browser.wheel(-1, options: "deltaMode: WheelEvent.DOM_DELTA_PAGE")
        XCTAssertEqual(page, 1)
    }

    func testWheelUsesSharedSafetyAndFailsClosedWhenMissingOrThrowing() async throws {
        let browser = try RefreshSafetyBrowser(pullToRefresh: true)
        defer { browser.close() }
        for unsafeContent in [
            "<textarea>Blurred draft</textarea>",
            "<div contenteditable='true'>Blurred draft</div>",
            "<input value='Blurred edit'>",
            "<iframe srcdoc='Empty'></iframe>",
            "<dialog open style='position:fixed;top:500px'>Confirm</dialog>",
            "<div role='dialog' style='position:absolute;top:2000px'>Confirm</div>"
        ] {
            try await browser.loadTimeline(extraHTML: unsafeContent)
            let clicks = try await browser.wheel(-72)
            XCTAssertEqual(clicks, 0, unsafeContent)
        }
        try await browser.loadTimeline(extraHTML: "<input id='editor'>")
        try await browser.run("""
            document.getElementById('editor').dispatchEvent(
              new Event('change', { bubbles: true, composed: true })
            );
            document.getElementById('editor').remove();
            """, world: .page)
        let stickyClicks = try await browser.wheel(-72)
        XCTAssertEqual(stickyClicks, 0)

        let missing = try RefreshSafetyBrowser(installSafety: false, pullToRefresh: true)
        defer { missing.close() }
        try await missing.loadTimeline()
        let missingClicks = try await missing.wheel(-72)
        XCTAssertEqual(missingClicks, 0)
        try await missing.run("""
            globalThis.__triColumnsRefreshSafety = { isUnsafe() { throw new Error('Unavailable'); } };
            """)
        let throwingClicks = try await missing.wheel(-72)
        XCTAssertEqual(throwingClicks, 0)
        try await missing.run("globalThis.__triColumnsRefreshSafety = { isUnsafe: () => undefined };")
        let malformedClicks = try await missing.wheel(-72)
        XCTAssertEqual(malformedClicks, 0)
    }

    func testWheelRequiresVisibleMatchingButtonNearTop() async throws {
        let browser = try RefreshSafetyBrowser(pullToRefresh: true)
        defer { browser.close() }
        for adjustment in [
            "button.style.display = 'none';",
            "button.style.position = 'absolute'; button.style.top = '600px';",
            "button.textContent = 'Unrelated action';"
        ] {
            try await browser.loadTimeline()
            try await browser.run("const button = document.getElementById('new-posts'); \(adjustment)")
            let clicks = try await browser.wheel(-72)
            XCTAssertEqual(clicks, 0, adjustment)
        }
    }

    func testQueuedWheelClickRechecksSharedSafety() async throws {
        let browser = try RefreshSafetyBrowser(pullToRefresh: true)
        defer { browser.close() }
        try await browser.loadTimeline()
        try await browser.run("globalThis.__deferRefreshFrames = true;")
        let queued = try await browser.wheel(-72)
        XCTAssertEqual(queued, 0)
        try await browser.run("""
            const textarea = document.createElement('textarea');
            textarea.value = 'Draft created before the next animation frame';
            document.body.append(textarea);
            globalThis.__refreshFrames.splice(0).forEach(callback => callback(performance.now()));
            """)
        let clicks: Int = try await browser.evaluate("__refreshClicks")
        XCTAssertEqual(clicks, 0)
    }

    func testPullScriptAlsoRejectsSubframesIfAccidentallyInjectedThere() async throws {
        let browser = try RefreshSafetyBrowser(pullToRefresh: true, pullInAllFrames: true)
        defer { browser.close() }
        try await browser.loadTimeline(extraHTML: "<iframe srcdoc='<main>Child</main>'></iframe>")
        let childNotInstalled: Bool = try await browser.evaluate("""
            document.querySelector('iframe').contentWindow.__triColumnsPullToRefreshInstalled !== true
            """)
        XCTAssertTrue(childNotInstalled)
    }
}

@MainActor
private final class RefreshSafetyBrowser: NSObject, WKNavigationDelegate {
    private let world = WKContentWorld.world(name: "TriColumnsSafety")
    private let webView: WKWebView
    private var navigationContinuation: CheckedContinuation<Void, any Error>?
    private var navigationTimeout: Task<Void, Never>?

    init(
        installSafety: Bool = true,
        pullToRefresh: Bool = false,
        pullInAllFrames: Bool = false
    ) throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let content = configuration.userContentController
        if installSafety {
            content.addUserScript(WKUserScript(
                source: try Self.resource("RefreshSafety"),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: world
            ))
        }
        if pullToRefresh {
            // These are event-algorithm tests, not compositor/physical trackpad tests.
            // Offscreen WKWebViews may suspend rAF. Only frame scheduling is stubbed
            // in the isolated world; wheel dispatch, layout, clocks, and timers are real.
            content.addUserScript(WKUserScript(
                source: """
                    globalThis.__refreshFrames = [];
                    globalThis.__deferRefreshFrames = false;
                    globalThis.requestAnimationFrame = callback => {
                      if (globalThis.__deferRefreshFrames) {
                        globalThis.__refreshFrames.push(callback);
                      } else {
                        callback(performance.now());
                      }
                      return 1;
                    };
                    """,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: world
            ))
            content.addUserScript(WKUserScript(
                source: try Self.resource("XPullToRefresh"),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: !pullInAllFrames,
                in: world
            ))
        }
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    static func resource(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent("Resources/\(name).js"),
            encoding: .utf8
        )
    }

    static func jsString(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    func load(_ html: String, host: String = "x.com") async throws {
        try await withCheckedThrowingContinuation { continuation in
            navigationContinuation = continuation
            navigationTimeout = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(15))
                } catch {
                    return
                }
                self?.finishNavigation(.failure(BrowserError.navigationTimedOut))
            }
            // Inline fixtures, srcdoc/about:blank frames, and a data: media URL only.
            // The base URL exercises the shipped hostname gate without loading it.
            webView.loadHTMLString("<!doctype html>\(html)", baseURL: URL(string: "https://\(host)/"))
        }
    }

    func loadTimeline(host: String = "x.com", extraHTML: String = "") async throws {
        try await load("""
            <style>body { margin: 0; } button { width: 200px; height: 40px; }</style>
            <aside id='outside'>Outside timeline</aside>
            <main id='timeline'>
              <button id='new-posts'>See new posts</button>
              <div id='nested' style='overflow-y:auto;height:40px;width:300px'>
                <div id='nested-content' style='height:300px'>Nested timeline</div>
              </div>
            </main>
            \(extraHTML)
            """, host: host)
        try await run("""
            globalThis.__refreshClicks = 0;
            document.getElementById('new-posts').addEventListener('click', () => {
              globalThis.__refreshClicks += 1;
            });
            """)
    }

    func evaluate<T: Sendable>(_ script: String, world requestedWorld: WKContentWorld? = nil) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script, in: nil, in: requestedWorld ?? world) { result in
                switch result {
                case .success(let value):
                    guard let typed = value as? T else {
                        continuation.resume(throwing: BrowserError.unexpectedJavaScriptResult)
                        return
                    }
                    continuation.resume(returning: typed)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func run(_ script: String, world: WKContentWorld? = nil) async throws {
        let _: Bool = try await evaluate("(() => { \(script)\n; return true; })()", world: world)
    }

    func isUnsafe() async throws -> Bool {
        try await evaluate("__triColumnsRefreshSafety.isUnsafe()")
    }

    func wheel(_ delta: Double, target: String = "#timeline", options: String = "") async throws -> Int {
        try await evaluate("""
            (() => {
              const event = new WheelEvent('wheel', {
                deltaY: \(delta), bubbles: true, composed: true, cancelable: true, \(options)
              });
              document.querySelector(\(try Self.jsString(target))).dispatchEvent(event);
              globalThis.__lastWheelDefaultPrevented = event.defaultPrevented;
              return globalThis.__refreshClicks;
            })()
            """)
    }

    func waitUntil(_ condition: String) async throws -> Bool {
        for _ in 0..<50 {
            let ready: Bool = try await evaluate(condition)
            if ready {
                return true
            }
            try await Task.sleep(for: .milliseconds(40))
        }
        return false
    }

    func close() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeAllUserScripts()
        navigationTimeout?.cancel()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishNavigation(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        finishNavigation(.failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        finishNavigation(.failure(error))
    }

    private func finishNavigation(_ result: Result<Void, any Error>) {
        navigationTimeout?.cancel()
        navigationTimeout = nil
        let continuation = navigationContinuation
        navigationContinuation = nil
        continuation?.resume(with: result)
    }

    private enum BrowserError: Error {
        case navigationTimedOut
        case unexpectedJavaScriptResult
    }
}
