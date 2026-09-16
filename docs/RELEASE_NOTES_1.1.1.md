# TriColumns 1.1.1

Reliability update addressing the eight findings from the September 2026
design and code review. Minimum supported macOS remains 14.

## Fixes

- Preserve existing files when a replacement download fails or is cancelled.
- Associate each download and its save/error UI with the window that started it.
- Keep automatic refresh paused after editing, including after focus changes.
  Share the conservative safety policy with X.com's pull-to-refresh gesture.
- Suppress automatic refresh for embedded frames, dialogs, media, native panels,
  and unknown editing state; reject stale navigation safety results.
- Apply URL settings only to changed columns, with confirmation before leaving
  potentially unsafe pages.
- Reject empty-host URLs and share URL validation between settings and the
  address field.
- Support user-directed HTTP browsing in WebKit, while indicating unencrypted
  connections and preserving HTTPS as the default.
- Show retryable navigation failures without surfacing normal cancellation or
  download-conversion events as errors.
- Close native popup windows when their page calls `window.close()`, and clean
  up related delegates, downloads, and timers on window shutdown.

## Verification

Run `swift test` for URL, settings, file-transaction, and isolated WebKit regression
coverage. Build the signed application with the generated Xcode project.
Automated WebKit fixtures are local and use a nonpersistent website data store.

For this release, all 45 tests passed in both Debug and Release configurations.
The signed universal application (arm64 and x86_64) passed strict signature
verification and launched its sample workspace. A separate signed Sandbox probe
also loaded HTTP successfully with the app's transport policy.

Manual validation is still needed for Powerbox-approved external-file saves and
external-volume destinations. The automated Sandbox save-panel probe could not
obtain a user-selection grant, so it did not verify that path. File preservation,
failed finalization, cancellation, and real WebKit download-origin routing are
covered by the regression suite without that grant.

This is a GitHub source release. App Store Connect submission and notarized
binary distribution are separate release operations. Authenticated X.com posting
and OAuth compatibility are not guaranteed by the local regression suite.
