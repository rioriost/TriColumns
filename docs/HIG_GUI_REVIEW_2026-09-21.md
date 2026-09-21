# TriColumns GUI review — 2026-09-21

## Scope and design contract

Implementation using `design-with-apple-hig`. Baseline: `acbe38c`, initially clean
working tree. Keep the three independent browsing columns, shared website data,
AppKit/WebKit architecture, macOS 14 deployment target, URL preferences, privacy
links and existing refresh/download safety behavior.

The page content remains primary. Each column has a quiet identity line and a
navigation row with standard symbols, a readable address field and localized
control names. These are column-local controls, not a replacement window-wide
`NSToolbar`. The Navigate menu exposes their actions and keyboard equivalents.
Use native controls, focus rings and semantic colors, with no added animation or
permission. Keep Japanese and English strings in the existing localization files.
Empty columns explain how to start; invalid settings return focus to the field
that needs correction. Retain explicit Save/Cancel and changed-column-only apply.

## Findings and changes

| ID | Evidence / impact | Change | Verification |
| --- | --- | --- | --- |
| GUI-01 | OBSERVATION: previous buttons exposed only `‹`, `›`, `↻` as names. Address text used an 11 pt monospaced font; column labels shared the narrow input row. | SF Symbols with localized per-column AX names and tooltips, 28 pt button frames, system-sized address text, separate identity row. | Pass: native screenshot and AX tree, Japanese dark appearance. |
| GUI-02 | OBSERVATION: browsing actions were absent from the menu bar. | Navigate menu with ⌘L, ⌘R, ⌘[ / ⌘], and ⌘1–3; commands disabled outside the main window or when history is unavailable. Window menu provides Minimize and Zoom. | Pass: column focus, location, back, forward, reload in running sample workspace; focused-column regression test. Window menu actions not exercised. |
| GUI-03 | OBSERVATION: a blank column provided no in-content explanation. | Native empty state and address-entry button; no new network request or saved setting. | Pass: initial blank column and return to blank through history. |
| GUI-04 | OBSERVATION: settings lacked instructions; runtime review also found uneven row spacing and a missing Tab focus loop. | Introductory text, evenly sized URL rows, native action buttons, explicit keyboard loop, focus restoration after validation. | Pass: screenshot, Tab/Shift-Tab through fields, Escape, Return validation, invalid field selected after closing alert. |
| GUI-05 | AUDIT: there was no minimum window content size. | 960 × 480 pt minimum content size. | Source/build verified. Dragging to a smaller size through the UI tool did not resize the window; actual minimum-size rendering remains unverified. |

Sizes and the two-row composition are product choices (`HEURISTIC`), not a claim
that Apple mandates these values. The accessibility page's macOS control sizing
guidance was considered, without importing iOS touch dimensions.

## Current primary sources

Retrieved 2026-09-21. HIG JavaScript-only pages were read using the skill's Apple
DocC reader. SDK pages were retrieved through Apple's Markdown endpoint.

| Type | Source | Applied scope |
| --- | --- | --- |
| APPLE-HIG | [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos) | Readable density, resizable windows, menus and keyboard input. |
| APPLE-HIG | [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) | Familiar symbols, logical grouping, menu access to actions; distinguished window toolbar guidance from this app's local pane controls. |
| APPLE-HIG / ACCESSIBILITY | [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) | System colors, descriptive labels, appropriate controls and keyboard alternatives. |
| APPLE-SDK | [NSImage symbol initializer](https://developer.apple.com/documentation/appkit/nsimage/init(systemsymbolname:accessibilitydescription:)) | Native symbol images; available since macOS 11. |
| APPLE-SDK | [setAccessibilityLabel](https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol/setaccessibilitylabel(_:)) | Short descriptions of accessibility elements. |
| APPLE-RESOURCE | [Apple releases](https://developer.apple.com/news/releases/) | macOS 27.0 (26A428) and Xcode 27 (27A266a), public releases dated September 14, 2026. Feed also lists macOS 27.2 beta; no beta-only APIs adopted. |

## Verification

- Environment: macOS 27.0 (26A428), Xcode 27.0 (27A266a), MacOSX27.0 SDK;
  deployment target remains macOS 14.0. AppKit, keyboard and pointer input.
- Debug GUI build: passed using a separate `st.rio.tricolumns.higpreview` app
  identity, ad-hoc signing and the existing entitlements. Installed app, real
  website session and saved preferences were not replaced. Sample data is fictional.
- Release build: passed with normal product identity and ad-hoc local signing.
  This is not a distribution archive or App Store submission.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`: **46 tests,
  0 failures**. Added a regression check that a field editor identifies only its
  containing column, and a separate field cannot be mistaken for a column.
- Both localization files pass `plutil -lint`; `git diff --check` passes.
- Runtime: Japanese dark appearance, main window, empty column, sample workspace,
  settings, invalid URL sheet and focus return. AX inspection confirms meaningful
  names for navigation buttons and address fields. Standard keyboard navigation
  preference `AppleKeyboardUIMode` was 2; actual VoiceOver speech was not tested.
- Runtime: ⌘1–3 selects the intended URL field; ⌘L retains the current column;
  ⌘[ / ⌘] moves the selected column through history; ⌘R reloads its sample page.
  Tab/Shift-Tab visits settings URL fields in order; Escape closes settings;
  Return invokes validation and the alert returns selection to the invalid field.
- Build logs: `.build/hig-review/build.log`, `release-build.log`, `tests.log`.
  The build reports the standard skipped App Intents metadata extraction warning
  because the app has no AppIntents dependency.
- Release preparation follow-up: Japanese and English main-window and Settings
  rendering inspected using isolated copies of the 1.1.2 (8) archived binary.
  The distribution archive and another 46-test Release run passed. Store upload
  status is recorded separately in `APP_STORE_PREPARATION_1.1.2.md`.

## Coverage limits

Not run: macOS 14 runtime, actual minimum-window rendering, light appearance,
Increase Contrast/Reduce Transparency, VoiceOver speech,
Full Keyboard Access/Switch Control, and Window menu actions. No new motion is
introduced. Screenshots and AX inspection do not establish assistive-technology
conformance or complete HIG compliance. Existing browsing regression tests pass,
but arbitrary third-party website layouts are outside the native GUI change.

Local, ignored screenshots from the final Debug preview:
[main window](../.build/hig-review/main-dark-ja.jpg) and
[settings](../.build/hig-review/settings-dark-ja.jpg).
