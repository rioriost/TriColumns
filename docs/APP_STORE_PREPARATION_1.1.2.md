# App Store Review Preflight — 2026-09-21

- App / platform: TriColumns / macOS
- Version / build: 1.1.2 / 8
- Submission type: Update
- Guidelines checked: last updated June 8, 2026; retrieved September 21, 2026
- Readiness: **READY WITH MANUAL CONFIRMATIONS**
- Counts: BLOCKER 0 / WARNING 1 / MANUAL 3 / PASS 7 / NOT APPLICABLE 1

## Actionable findings

### Resolved — Build upload and selection

After the account holder refreshed Xcode sign-in, the retry succeeded at
2026-09-21 12:22 JST (`Upload succeeded`, `EXPORT SUCCEEDED`, exit 0).
TestFlight shows version 1.1.2 build 8 as Ready to Submit after Apple processing.
Build 8 was selected and saved in the 1.1.2 App Store draft. The upload date shown
by App Store Connect is September 21, 2026, 12:22.

- App Store Connect build ID: `188b147e-39c5-44ab-9f75-376c6054ffd7`.
- Uploaded archive executable SHA-256:
  `57e9510a493780bab608f550320e6d1d8e889853e45c0ed1cae78e6859657933`.
- Final upload evidence: `.xcode-derived/appstore-1.1.2-8/upload-retry-latest.log`.

Source: [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/).

### Resolved — Screenshot processing verification (2.3 metadata)

Correction: the earlier 2 / 10 count proved registration only. Add for Review
reported screenshots still uploading, and visual inspection showed failed image
tiles. The files had JPEG data with PNG extensions. All four files were converted
to actual RGB PNG (1440 x 900), replaced, and visually verified in both locales.
Add for Review then succeeded; the draft lists 1.1.2 (8) as Ready for Review.
The final Submit for Review control is available and has not been clicked.

Intended Japanese and English (US) order:
`01-three-column-workspace.png`, `03-column-settings.png`. These are the current
assets in `AppStoreAssets/Screenshots`. English uses its own localized images,
not inherited Japanese images. Published 1.1.1 was not changed.

The earlier file chooser failure was resolved with the supported browser chooser
flow. Each image was uploaded separately to preserve order. When removing all
English images, App Store Connect temporarily inherited Japanese images; Edit
was used to enable a custom English set before uploading. The legacy
`02-research-dashboard.png` files were not uploaded.

Source: [App Review Guidelines, 2.3](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata).

### WARNING — Existing category mismatch (2.3.5)

App Store Connect identifies the app as Social Networking; the app bundle uses
Productivity. The browser can serve both workflows, but the category should be
reviewed for the intended primary use. Existing categorization was retained.

Source: [Guideline 2.3.5](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata).

### MANUAL — Review contact

The draft shows the existing contact name, but phone and email values were not
exposed in the accessibility snapshot. This does not establish whether stored
values are absent. Confirm usable contact details before submission; none were
invented or replaced. Add for Review accepted the existing contact fields, but
this does not independently verify that the contact is reachable.

Source: [Guideline 2.1](https://developer.apple.com/app-store/review/guidelines/#app-completeness).

### MANUAL — Runtime coverage

macOS 27 Japanese/English dark rendering and relevant keyboard behavior were
inspected. macOS 14, light appearance, the actual minimum window size, VoiceOver
speech and enhanced accessibility settings remain unverified. See
[GUI review](HIG_GUI_REVIEW_2026-09-21.md) for exact coverage.

Source: [Guideline 2.1](https://developer.apple.com/app-store/review/guidelines/#app-completeness).
These are validation limits, not a claim that every listed test is an Apple
submission requirement.

### MANUAL — Rights and regional obligations

Existing content-rights, trader and age-rating declarations were retained.
Current storefront availability shows 148 available and 27 unavailable regions.
The developer must confirm applicable third-party content rights and regional
obligations; the preflight does not establish legal authorization for arbitrary
websites loaded by users.

Source: [Guideline 5 and 5.2](https://developer.apple.com/app-store/review/guidelines/#legal).

## Passed checks

1. **Build integrity:** archive succeeded with Xcode 27.0 (27A266a), macOS 27.0
   (26A428), macOS 14 deployment target, arm64 and x86_64. Archive signature passes
   strict verification. Bundle identity and versions are st.rio.tricolumns,
   1.1.2 and 8. Distribution export/upload succeeded after authentication.
2. **Regression checks:** Release tests passed, 46 tests / 0 failures. GUI
   behavior and accessibility names were inspected; this is not a claim of full
   accessibility conformance.
3. **Privacy:** in-app Privacy Policy and Support menu paths exist; hosted policy
   and support pages were reachable. App Store Connect declares no developer
   data collection. No analytics, ads or new permissions were introduced.
4. **Sandbox and review access:** archive has sandbox, outbound network and
   user-selected read/write entitlements; no debug entitlement. Bundled fictional
   sample pages permit offline review without an account. Review notes explain
   the web-content-only HTTP exception and file access.
5. **Draft metadata:** created 1.1.2 in Prepare for Submission; Japanese and
   English What's New and English review notes saved. Existing automatic release
   after approval, all-user release and retained ratings remain selected. The
   currently published 1.1.1 (7) was observed as Ready for Distribution. All
   displayed prices, including Japan and US, were zero.

6. **Upload and selection:** successful export/upload, Apple processing completed,
   and build 8 selected and saved in the App Store draft.
7. **Screenshots:** all four files are RGB PNG at 1440 x 900. Japanese and
   English thumbnails were visually verified after upload; Add for Review now
   accepts the images. Registration counts alone were not sufficient evidence.

**NOT APPLICABLE:** developer-operated accounts, account deletion, IAP,
subscriptions, ads and tracking. Third-party websites can have their own accounts
and policies; these are distinct from developer-operated app features.

## Coverage summary

| Family | Status | Evidence or reason |
|---|---|---|
| Safety | MANUAL | General browser; existing age/content declarations retained. |
| Performance | PASS | Archive/tests pass; upload, processing and build selection complete. |
| Business | PASS / N/A | Free app; no developer purchases or subscriptions. |
| Design | PASS / MANUAL | Native GUI inspected; documented runtime coverage limits. |
| Legal | PASS / MANUAL | Privacy paths and declaration checked; rights/regional review remains. |

## Evidence reviewed

- Current [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/):
  introduction and Safety, Performance, Business, Design and Legal families;
  especially 2.1, 2.3, 2.3.5, 5.1.1 and 5.2.
- [Create a new version](https://developer.apple.com/help/app-store-connect/update-your-app/create-a-new-version/)
  and Apple's build-upload instructions above.
- App Store Connect: version 1.1.1, new 1.1.2 draft, App Information, App Privacy,
  Pricing and Availability. App ID 6791172657.
- `project.yml`, generated Xcode project, `AppBundle/Info.plist`, entitlements,
  native sources, localizations, tests, privacy policies and release notes.
- Local ignored evidence: `.xcode-derived/appstore-1.1.2-8/`, containing
  `TriColumns.xcarchive`, `archive.log`, `tests.log`, `upload.log`,
  `upload-retry-latest.log`,
  `ExportOptions.plist`, `preflight-inventory.json` and screenshot layouts.
- Archive app: `.xcode-derived/appstore-1.1.2-8/TriColumns.xcarchive/Products/Applications/TriColumns.app`.
- [Japanese policy](https://github.com/rioriost/TriColumns/blob/main/docs/PRIVACY_POLICY.md)
  and [support](https://github.com/rioriost/TriColumns/issues).

## Final gate

Confirm contact details, relevant runtime coverage and rights/regional items
before submission. The selected 1.1.2 (8) is the build uploaded from the audited
archive; TestFlight processing and the saved draft selection were verified.
The App Store version remains Prepare for Submission, with one Ready for Review
item in the submission draft. Add for Review succeeded at 12:29 JST.
**Final Submit for Review has not been performed.** The preflight skill requires
confirmation after presenting the remaining warning and manual items.
