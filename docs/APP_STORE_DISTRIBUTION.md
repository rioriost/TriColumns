# App Store Distribution

## Project Configuration

- Product: `TriColumns`
- Bundle identifier: `st.rio.tricolumns`
- Team: `23889H77KX`
- Minimum macOS version: macOS 14
- Signing: automatically managed by Xcode
- Hardened Runtime: enabled
- App Sandbox: enabled
- App category: Productivity
- Encryption declaration: no non-exempt encryption

The app requests only these sandbox capabilities:

- outgoing network connections for web browsing;
- user-selected file read/write access for uploads and downloads;
- camera access for website capture requests;
- microphone access for audio and live conversation features.

There is no incoming-network, contacts, calendar, location, automation, or
full-disk entitlement.

## Privacy

`Resources/PrivacyInfo.xcprivacy` declares `UserDefaults` access with approved
reason `CA92.1`. The app does not include tracking code and does not send its
own analytics or account data to the developer.

App Store Connect privacy answers must distinguish TriColumns itself from the
third-party websites shown in `WKWebView`. Website operators may collect data
under their own policies. The store listing should link to a TriColumns privacy
policy that explains this distinction.

## Archive Checklist

1. Confirm the selected icon renders correctly at all macOS sizes.
2. Increment `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` as needed.
3. Confirm that the Apple Distribution certificate is available to Xcode.
4. Set the run destination to **Any Mac** and choose **Product > Archive**.
5. In Organizer, validate and distribute with **App Store Connect**.
6. Confirm the exported app has App Sandbox enabled and does not contain the
   development-only `com.apple.security.get-task-allow` entitlement.

The locally installed Release build is signed with Apple Development for
testing. It is not the App Store upload artifact. Developer ID Application is
also not used for Mac App Store submission.

## Review Notes

Explain that TriColumns is a fixed three-column WebKit browser. It does not
use X APIs, scrape content, automate engagement, impersonate Safari, or bundle
X credentials. Users interact directly with the normal websites loaded in the
three independent views. TriColumns is not affiliated with or endorsed by
X Corp.
