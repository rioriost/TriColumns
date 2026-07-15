# TriColumns Implementation Plan

## Purpose

TriColumns started as a fixed three-column viewer for X.com. The next
step is to treat it as a small column-oriented browser: each column is a real
browser context, while the window remains deliberately simpler than a general
purpose browser.

The initial product boundary is:

- three equal-width columns that follow window resizing;
- shared cookies and website data across columns;
- normal website JavaScript, forms, uploads, downloads, and editing commands;
- conservative handling of permissions and links that leave the current page;
- automatic reload that never knowingly destroys a draft or interrupts media;
- no tab manager, extension system, bookmark manager, or browser sync.

## Current Baseline

- Three `WKWebView` instances use one persistent `WKWebsiteDataStore`.
- Content JavaScript and back/forward gestures are enabled.
- Basic navigation and edit commands are available.
- The standard WebKit user agent is used without impersonating Safari.
- Columns reload every 30 minutes unless disabled or overridden.
- Each column URL is configurable and persists in `UserDefaults`.

## Phase 1: Safe Website Interaction

Goal: make posting and interactive pages usable without losing user work.

- Implement the WebKit file chooser with `NSOpenPanel` for images and videos.
- Support multiple file selection when requested by the page.
- Defer automatic reload while a compose field contains text, an upload is
  selected, a modal is open, an editable control has focus, or media is playing.
- Present JavaScript alert, confirmation, and text-input dialogs.
- Handle requested popup windows without replacing an unrelated column.
- Keep X.com links in the originating column where practical.

Acceptance checks:

- X.com's media button opens a native file picker and returns selected files.
- Cancelling the picker does not change the page.
- A draft post survives an automatic reload opportunity.
- `alert`, `confirm`, `prompt`, and `target=_blank` have visible behavior.

## Phase 2: Browser File and Link Handling

Goal: cover normal browser behavior that crosses the WebKit/OS boundary.

- Convert navigation responses that WebKit cannot display into downloads.
- Show a native save panel and report failed downloads.
- Send non-web URL schemes such as `mailto:` to macOS.
- Preserve HTTP and HTTPS navigation inside WebKit unless a popup is requested.

Acceptance checks:

- A downloadable response opens a save panel and writes the selected file.
- Cancelling a download leaves no partial destination file.
- External application links do not produce a blank WebKit page.

## Phase 3: Device Permissions

Goal: support X Spaces and browser features that request capture devices.

- Add camera and microphone usage descriptions to the app bundle.
- Allow WebKit to prompt for media capture only for secure X.com origins.
- Deny capture requests from untrusted or insecure origins.

Acceptance checks:

- A secure X.com media request reaches the macOS permission prompt.
- The same request from another origin is denied.

## Phase 4: Integration and Distribution

Goal: verify the complete executable and update the installed application.

- Run Swift and Xcode release builds.
- Install and verify the signed app bundle in `/Applications`.
- Perform a manual smoke test for login, posting, upload, download, popup, and
  permission behavior when an authenticated X.com session is available.

## Deferred Work

These features need separate product decisions or cannot be made equivalent to
Safari solely through `WKWebView`:

- Web Push and macOS notification integration.
- Location permission and location-aware posting.
- Passkeys and authentication flows that reject embedded browsers.
- Download history, progress UI, and interrupted-download resume.
- A configurable column count beyond the fixed three-column layout.
- A site-permission management screen.

Drag and drop and clipboard image paste are initially delegated to standard
`WKWebView` behavior. Native interception should only be added after a manual
test demonstrates a specific failure, because intercepting these events can
break the page's own handlers.

## Reload Policy

Full-page reload remains a fallback rather than the primary update mechanism.
Sites such as X.com normally retrieve timeline changes through JavaScript and
network APIs. The timer therefore uses a long interval and skips reload when
the page appears unsafe to interrupt. Manual reload always remains available.
