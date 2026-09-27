# macOS 27.2 Beta 2 Compatibility Report

## Summary

On September 27, 2026, **22 of 23 runtime checks passed** on the user's
MacBook Air. Swift compilation, an ad-hoc-signed Release build, and application
launch succeeded. Cancelling a download's save panel reproducibly displayed a
download-failure alert.

This is a bounded compatibility check, not a certification of all browser
features. No older macOS version was tested, so the download issue cannot be
attributed specifically to macOS 27.2.

## Environment

| Item | Value |
| --- | --- |
| Tested revision | `ef1cff0` — Add macOS 27 support and bump version to 1.1.0 |
| Application version | 1.1.0 (4) |
| Machine | MacBook Air, as identified by the user |
| Architecture | `arm64` |
| macOS | 27.2, build `26B5091g` |
| Beta designation | Beta 2, as identified by the user |
| Xcode | 27.0, build `27A266a` |
| macOS SDK | 27.0 |
| Deployment target | macOS 14.0 |
| Test date | September 27, 2026 (JST) |

## Build and Launch Results

| Check | Result |
| --- | --- |
| `swift build` | Passed |
| Normal Xcode Release build | Blocked by a missing Mac Development signing certificate/private key for the configured team |
| Xcode Release build with ad-hoc signing | Passed |
| `codesign --verify --deep --strict` | Passed |
| Sandbox, outgoing network, user-selected read/write entitlements | Present |
| Privacy manifest and English/Japanese localization plist validation | Passed |
| Unmodified Release application launch | Passed |

The signing failure was an environment limitation, not a compiler failure.
The ad-hoc build used command-line overrides without changing the project:

```sh
xcodebuild -quiet \
  -project TriColumns.xcodeproj \
  -scheme TriColumns \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /path/to/temporary/derived-data \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  build
```

The unmodified Release app was launched with `--sample-workspace`,
`TRICOLUMNS_RELOAD_SECONDS=0`, and empty command-line overrides for
`column1URL`, `column2URL`, and `column3URL`. `NSRunningApplication` reported
that launch had completed, and CoreGraphics reported one onscreen native
window. The captured runtime log was empty. The app was closed normally after
this check.

## Runtime Test Method

The repository had no automated test targets. A temporary in-process Swift
harness was appended to a generated copy of `Sources/TriColumns/main.swift`
immediately before `app.run()`. The production class implementations were
unchanged.

The harness used the Release app's bundled resources, Swift 6, optimization,
ad-hoc signing, the production sandbox entitlements, and a separate bundle
identifier, `st.rio.tricolumns.compatibility-test`. Blank startup URL overrides
and the separate application identity isolated the checks from the user's
configured pages and normal application cookie store.

Most checks used the fictional bundled sample pages. HTTPS navigation used
`https://example.com`. X pull-to-refresh checks used a synthetic local document
with an `https://x.com/` base URL and the production user script; they did not
use a logged-in X session.

Accessibility automation was unavailable. Native actions and panel responses
were invoked inside the test process rather than through external mouse or
keyboard automation. Automatic-reload checks invoked the existing timer action
directly rather than waiting for the configured interval.

## Runtime Results

| # | Check | Result |
| --- | --- | --- |
| 1 | Startup creates exactly three columns and three `WKWebView` instances | Passed |
| 2 | Equal-width layout at 1,000- and 1,400-point content widths, within one point | Passed |
| 3 | Sample-workspace action loads bundled HTML, JavaScript, CSS, and images | Passed |
| 4 | Japanese sample content renders in all columns | Passed |
| 5 | English sample content renders in all columns | Passed |
| 6 | Cookie sharing across all three WebKit stores; test cookie removed afterward | Passed |
| 7 | Settings opens with three fields and cancels without saving | Passed |
| 8 | Configured pages restore and sample mode does not overwrite configured URLs | Passed |
| 9 | Address entry normalizes `example.com` to HTTPS without navigating other columns | Passed |
| 10 | Back, forward, and manual reload | Passed |
| 11 | Automatic reload preserves a textarea draft | Passed |
| 12 | Automatic reload is suppressed for a focused input | Passed |
| 13 | Automatic reload is suppressed for a visible modal | Passed |
| 14 | Automatic reload is suppressed for a synthetic selected file | Passed |
| 15 | Automatic reload proceeds when the document is safe | Passed |
| 16 | Native JavaScript alert completion | Passed |
| 17 | Native JavaScript confirmation completion | Passed |
| 18 | Native JavaScript prompt returns the entered value | Passed |
| 19 | Popup content loads without replacing a column | Passed |
| 20 | Native multiple-file picker preserves options and cancels without selecting a file | Passed |
| 21 | Download save-panel cancellation | Failed |
| 22 | X pull-to-refresh does not trigger at 71 pixels, triggers at 72 pixels, and observes cooldown | Passed |
| 23 | X pull-to-refresh is suppressed while editing | Passed |

The final full-run summary was:

```text
COMPAT SUMMARY passed=22 failed=1
```

An earlier harness iteration had three JavaScript duplicate-`const` errors.
These were test-harness errors, corrected by adding local scope before the
final full run. They are not application failures.

## Finding: Download Cancellation Displays a Failure Alert

### Reproduction

1. Load a bundled sample page in the isolated test app.
2. Create and click an anchor with a `data:text/plain` URL and
   `download="tricolumns-compatibility.txt"`.
3. Wait for the native `NSSavePanel` and verify the suggested filename.
4. Cancel the save panel.

Expected: the download is cancelled without displaying a failure alert.

Observed: an `_NSAlertPanel` appears with the localized title
**「ダウンロードに失敗しました」**. The runtime log also contains:

```text
sandbox_extension_issue_file failed for : 2 (No such file or directory)
```

The behavior reproduced in the full suite and in isolated single-check runs.
The final isolated run dismissed the alert and exited normally:

```text
COMPAT DETAIL remaining-sheet-type=_NSAlertPanel
COMPAT DETAIL cancellation-alert-text=["ダウンロードに失敗しました", ""]
COMPAT FAIL native-download-save-panel-cancel: failed("Download cancellation displayed an unexpected panel or error alert")
COMPAT SUMMARY passed=0 failed=1
```

### Relevant Implementation

Line references are for the tested revision, `ef1cff0`:

- [`Sources/TriColumns/main.swift`](../Sources/TriColumns/main.swift),
  lines 350–353: save-panel cancellation calls `completionHandler(nil)`.
- Lines 370–375: `download(_:didFailWithError:resumeData:)` displays an alert
  for every download failure, without distinguishing user cancellation.
- Lines 582–585: `showDownloadError(_:)` creates the observed alert.

The existing failure handling is consistent with the observed behavior.
The underlying error code and any causal connection to the sandbox log were
not established. No fix was applied during this investigation.

## Limitations

The following were not verified:

- Behavior on an older macOS version, Developer ID or App Store distribution
  signing, and notarization.
- Authenticated X login, posting, and the current live X page structure.
- Successful real-file upload or download completion.
- Physical trackpad gestures, drag and drop, clipboard interactions, and
  media-playback protection.
- Long-duration operation and actual scheduled timer firing.
- Visual appearance through manual inspection or external UI automation.

The unmodified Release app received a launch smoke test; the 23 detailed
runtime checks ran in the instrumented, separately identified test app.
These results should not be interpreted as complete end-to-end coverage of
the installed application.

## Evidence and Changes

The local session retained the report, harness source, and these logs:

| Artifact | Contents |
| --- | --- |
| `compatibility-swift-build.log` | Successful Swift build |
| `compatibility-xcode-build.log` | Normal signing failure |
| `compatibility-xcode-adhoc-build.log` | Successful quiet ad-hoc Release build |
| `compatibility-release-runtime.log` | Empty log from the Release launch smoke test |
| `compatibility-runtime-tests-final.log` | Final full run: 22 passed, 1 failed |
| `compatibility-download-reproduction-final.log` | Isolated download-cancellation reproduction |
| `compatibility-harness.swift` | Temporary in-process test source |

These session-local artifacts are not committed or a permanent repository
test suite. The harness process exit status did not encode assertion failures;
the `COMPAT SUMMARY` and `COMPAT FAIL` records are the result indicators.

All test apps were stopped, and temporary app bundles and Xcode build products
were removed. The investigation did not modify production source, project
configuration, or the installed application. The worktree was clean after the
checks; this report is the subsequent documentation change.
