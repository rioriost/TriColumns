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

The Swift Package remains available for compiler checks:

```sh
swift build
```

## Columns

Column URLs are configured from **TriColumns > Settings** and stored in the
app's `UserDefaults` container. The defaults are:

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

## Browser Integration

- Native image and video file selection, including multiple selection.
- JavaScript alert, confirmation, and text-input dialogs.
- Popup windows without replacing an existing column.
- Native save panels for downloads and macOS handling for external URL schemes.
- Automatic reload suppression while editing, uploading, viewing a modal, or
  playing audio or video.
- On X.com, an additional upward scroll at the top activates X's visible
  **See new posts** control, similar to pull-to-refresh on iOS. It does nothing
  when no buffered posts are available.
- Standard WebKit drag-and-drop and clipboard behavior.

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

## License

TriColumns is released under the [MIT License](LICENSE).
