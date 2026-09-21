# TriColumns

TriColumns is a lightweight three-column web browser for macOS. Each column is
an independent `WKWebView`, while cookies and website data are shared within
the app.

## Build

Generate the Xcode project and build the app:

```sh
xcodegen generate
xcodebuild -project TriColumns.xcodeproj -scheme TriColumns build
```

For a local Release build installed at `/Applications/TriColumns.app`:

```sh
scripts/install_app.sh
```

The Swift Package supports compiler checks and regression tests:

```sh
swift build
swift test
```

## Columns

Column URLs are configured from **TriColumns > Settings** and stored in the
app's `UserDefaults` container. Saving settings only navigates columns whose
configured URLs changed; potentially unsafe changes require confirmation.
The defaults are:

- Column 1: empty
- Column 2: `https://x.com/notifications`
- Column 3: `https://x.com/home`

**TriColumns > Open Sample Workspace** loads three bundled, fictional pages
without changing those saved URLs. **Open Configured Pages** returns to the
saved configuration. The sample workspace requires no network connection or
third-party account.

By default, non-empty columns reload every 30 minutes. Override the interval in
seconds when running the Swift Package directly:

```sh
TRICOLUMNS_RELOAD_SECONDS=3600 swift run TriColumns
```

Set the value to `0` to disable automatic reload.

## Keyboard and Interface

The **Navigate** menu operates on the column containing keyboard focus:

- **⌘1 / ⌘2 / ⌘3** selects a column’s address field.
- **⌘L** selects the current column’s address; **⌘R** reloads its page.
- **⌘[ / ⌘]** goes back or forward in that column.
- **⌘,** opens Settings. Tab and Shift-Tab move between URL fields;
  Return saves and Escape cancels.

Column headers use system symbols, localized accessibility labels, and larger
address text. Empty columns offer an address-entry action. The main window has a
960 × 480 pt minimum content size to keep all three columns’ controls available.

See [GUI verification](docs/HIG_GUI_REVIEW_2026-09-21.md) for evidence and limits.

## Browser Integration

- Native image and video file selection, including multiple selection.
- JavaScript alert, confirmation, and text-input dialogs.
- Popup windows without replacing an existing column.
- Native save panels for downloads and macOS handling for external URL schemes.
- Downloads keep an existing destination intact until the new file has finished,
  and show save panels in the originating window.
- HTTP and HTTPS browsing, with an orange address and a warning tooltip for
  unencrypted HTTP connections. Failed navigation has an explicit retry action.
- Automatic reload suppression while editing, uploading, viewing a modal, or
  playing audio or video.
- On X.com, an additional upward scroll at the top activates X's visible
  **See new posts** control, similar to pull-to-refresh on iOS. It does nothing
  when no buffered posts are available.
- Standard WebKit drag-and-drop and clipboard behavior.

After an edit, automatic refresh stays paused for the lifetime of that document,
even after focus leaves the editor. Pages with embedded frames or uninspectable
editing state are conservatively excluded from automatic refresh. Manual reload
is always available and may discard unsaved work. X.com's pull gesture uses the
same safety policy but only activates the site's existing new-posts control.

This app uses WebKit but does not embed Safari or share Safari's cookies. The
first launch may require signing in to websites again.

## App Store

The Xcode target uses bundle identifier `st.rio.tricolumns`, App Sandbox,
outgoing network access, and user-selected read/write file access. It does not
request camera, microphone, location, contacts, or automation access.
`PrivacyInfo.xcprivacy` declares local `UserDefaults` use and no tracking or
collected data.

An Apple Distribution certificate and an App Store provisioning profile are
required when exporting an archive for App Store Connect.

Privacy policies: [日本語](docs/PRIVACY_POLICY.md) / [English](docs/PRIVACY_POLICY.en.md)

## Design

See [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md).
The [September 2026 review](docs/DESIGN_CODE_REVIEW_2026-09-16.md) records the
issues addressed in [1.1.1](docs/RELEASE_NOTES_1.1.1.md).
The GUI improvements are documented in [1.1.2](docs/RELEASE_NOTES_1.1.2.md).

## License

TriColumns is released under the [MIT License](LICENSE).
