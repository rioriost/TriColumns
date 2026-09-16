# TriColumns 1.1.1 App Store submission

Date: 2026-09-16 (JST)

- App / platform: TriColumns / macOS 14 and later
- App Store Connect ID: `6791172657`
- Bundle / team: `st.rio.tricolumns` / `23889H77KX`
- Source baseline: `1184a4e`, plus the build 7 changes described below
- Xcode: 27.0 (`27A266a`)
- Intended submission: version 1.1.1, build 7, update to published 1.1.0 (5)
- Existing release setting: automatic after approval, all users, retain ratings

## Build and upload evidence

Build 6 was archived, tested, and uploaded successfully at 16:56:40 JST.
Preflight then identified a missing in-app privacy policy link under
[Guideline 5.1.1(i)](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage).
Build 7 adds Japanese and English Privacy Policy and Support menu entries and
increments the build number in both project definitions. The links use the
existing public repository policy and support destinations.

Build 7 archive succeeded, strict signature verification passed, and all 45
Release regression tests passed with no failures. The app is universal
(`arm64` and `x86_64`). The actual archived app was launched; the new menu
entries and all three bundled sample pages were observed. The test instance
was then closed, leaving the original installed app running.

App Store upload used automatic distribution signing, with Apple Distribution
selected in the distribution log. Xcode reported `Upload succeeded` and
`EXPORT SUCCEEDED` at 16:59:44 JST. This proves upload, not App Review submission.

Local evidence is in `.xcode-derived/appstore-1.1.1-7/`: `archive.log`,
`tests.log`, `upload.log`, `preflight-inventory.json`, and `TriColumns.xcarchive`.
The export options are in `.xcode-derived/appstore-1.1.1-6/ExportOptions.plist`.

## Store preparation and preflight

The current Apple [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
and [submission workflow](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app)
were checked on 2026-09-16.

Japanese and English release notes were entered and saved. Existing descriptions
and three screenshots per locale were retained. Review notes explain the
offline sample workspace, native browser functionality, Sandbox permissions,
absence of developer-operated tracking and purchases, and the browser-specific
`NSAllowsArbitraryLoadsInWebContent` justification.

| Family | Finding | Evidence |
|---|---|---|
| Safety | PASS for inspected scope | General WebKit browser; unrestricted web access, social content and website advertising declared in age questionnaire; 16+ global / regional variants; no medical or hardware-control features. |
| Performance | MANUAL coverage limitation | Archive and 45 tests passed; archived app sample runtime passed. Powerbox-authorized external-volume saves, macOS 14 hardware and third-party OAuth/posting were not qualified in this run. |
| Business | PASS for inspected scope | Existing free prices across 175 price entries; no StoreKit, subscriptions, payment SDK or developer-operated ads in source. |
| Design | PASS with metadata warning | Three independent native browser columns, settings, navigation, file panels and offline sample pages. Store category remains Social Networking while bundle category is Productivity. |
| Legal | PASS for inspected technical scope | Privacy manifest: no tracking/collection and UserDefaults reason CA92.1; public policy reachable; build 7 supplies in-app links. Existing content-rights and trader declarations retained. |

The category discrepancy is a pre-existing metadata warning under
[Guideline 2.3](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata),
not a proven submission blocker. Runtime coverage limitations are recorded
against [Guideline 2.1](https://developer.apple.com/app-store/review/guidelines/#app-completeness).
Legal rights and regional compliance are developer declarations, not independently
verified legal conclusions. Existing availability is 148 available countries or
regions, with 27 EU countries unavailable; availability was not changed.

## Current gate

SUBMITTED: Waiting for Review, verified in the App Review details page at
2026-09-16 17:04 JST. Submission ID:
`e6836146-6d22-4f07-b881-bfeb38466a75`.

The contact phone and email controls appeared blank to the browser tools.
They were initially treated as missing, and the user was asked for values.
However, App Store Connect accepted Add for Review, marked the item Ready to
Submit, and accepted final submission without a contact error. No contact
values were changed. The initial assumption that these controls blocked
submission was therefore withdrawn; no additional user reply is needed.

Build 7 completed processing (TestFlight: Ready to Submit) and was selected and
saved for version 1.1.1. Its App Store Connect build ID is
`07741384-e97f-465d-8f97-3fc3972a3379`.
The success dialog stated that one item was submitted. The App Review page
then showed version 1.1.1 (7), Waiting for Review, with the submission timestamp.
Approval and publication have not occurred. Automatic release after approval
remains selected.
