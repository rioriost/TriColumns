# App Store Review Preflight — 2026-09-21

- App / platform: TriColumns / macOS
- Version / build: 1.1.2 / 8
- Submission type: Update
- Guidelines checked: last updated June 8, 2026; retrieved September 21, 2026
- Readiness: **NOT READY**
- Counts: BLOCKER 2 / WARNING 1 / MANUAL 3 / PASS 5 / NOT APPLICABLE 1

## Actionable findings

### BLOCKER — Build upload and selection

The Release archive succeeded, but export/upload exited 70 with
`error: exportArchive Failed to Use Accounts`. Xcode reports that App Store
Connect access is required for the configured team. The 1.1.2 draft has no build.
The account holder must complete Xcode setup and refresh Apple Accounts sign-in.
Then retry export from the existing archive, verify successful upload and Apple
processing, select build 8, and save. These are separate completion gates.

Source: [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/).

### BLOCKER — Screenshot replacement incomplete (2.3 metadata)

Two current screenshots per locale are prepared in `AppStoreAssets/Screenshots`
(`01-three-column-workspace.png` and `03-column-settings.png`). The in-app
browser's documented file chooser timed out both through the upload button and
the file input. Native access to the Codex host app is prohibited by the tool.
No current screenshot upload succeeded.

The Japanese draft's inherited screenshots were removed before the upload
attempt and it currently shows **0 / 10**. English retains its three inherited
1.1.1 screenshots. Published 1.1.1 was not changed. Upload the two current images
for Japanese, replace the three old English images with the two current ones,
and verify both locales show the intended order and no processing errors.
Do not upload either legacy `02-research-dashboard.png` file.

Source: [App Review Guidelines, 2.3](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata).

### WARNING — Existing category mismatch (2.3.5)

App Store Connect identifies the app as Social Networking; the app bundle uses
Productivity. The browser can serve both workflows, but the category should be
reviewed for the intended primary use. Existing categorization was retained.

### MANUAL — Review contact

The draft shows the existing contact name, but phone and email values were not
exposed in the accessibility snapshot. This does not establish whether stored
values are absent. Confirm usable contact details before submission; none were
invented or replaced.

### MANUAL — Runtime coverage

macOS 27 Japanese/English dark rendering and relevant keyboard behavior were
inspected. macOS 14, light appearance, the actual minimum window size, VoiceOver
speech and enhanced accessibility settings remain unverified. See
[GUI review](HIG_GUI_REVIEW_2026-09-21.md) for exact coverage.

### MANUAL — Rights and regional obligations

Existing content-rights, trader and age-rating declarations were retained.
Current storefront availability shows 148 available and 27 unavailable regions.
The developer must confirm applicable third-party content rights and regional
obligations; the preflight does not establish legal authorization for arbitrary
websites loaded by users.

## Passed checks

1. **Build integrity:** archive succeeded with Xcode 27.0 (27A266a), macOS 27.0
   (26A428), macOS 14 deployment target, arm64 and x86_64. Archive signature passes
   strict verification. Bundle identity and versions are st.rio.tricolumns,
   1.1.2 and 8. Distribution export remains blocked as above.
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

**NOT APPLICABLE:** developer-operated accounts, account deletion, IAP,
subscriptions, ads and tracking. Third-party websites can have their own accounts
and policies; these are distinct from developer-operated app features.

## Coverage summary

| Family | Status | Evidence or reason |
|---|---|---|
| Safety | MANUAL | General browser; existing age/content declarations retained. |
| Performance | BLOCKER / PASS | Archive and tests pass; upload and build selection pending. |
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
  `ExportOptions.plist`, `preflight-inventory.json` and screenshot layouts.
- Archive app: `.xcode-derived/appstore-1.1.2-8/TriColumns.xcarchive/Products/Applications/TriColumns.app`.
- [Japanese policy](https://github.com/rioriost/TriColumns/blob/main/docs/PRIVACY_POLICY.md)
  and [support](https://github.com/rioriost/TriColumns/issues).

## Final gate

Resolve build upload/processing/selection and screenshot registration, then
confirm contact details, relevant runtime coverage and rights/regional items.
There is no selected 1.1.2 build to audit yet; only the local archive was audited.
**No submission action was performed.**
