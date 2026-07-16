# App Review Screen Recording

## Recording Setup

- Use the iPhone camera to film the physical Mac Studio display continuously.
- Keep the Mac model and OS details in App Review Notes; the requested recording
  itself should begin with launching the app.
- Hide notifications and unrelated personal information before recording.
- Use build `1.0.1 (3)` and keep the entire TriColumns window visible.
- Do not edit the recording in a way that obscures the continuous user flow.

## Suggested Flow

1. Start on the macOS desktop with TriColumns not running.
2. Launch TriColumns from `/Applications` so the app launch is visible.
3. Open **TriColumns > Open Sample Workspace**. Show that all three columns load
   fictional content without a login or network-dependent setup.
4. Resize the main window narrower and wider. Keep the three equal columns in
   frame.
5. Use Reload in one column. Click an address field, enter `example.com`, press
   Return, then use Back to return to the sample page.
6. Open **TriColumns > Settings**. For a clean public-page demonstration, set:
   - Column 1: `https://example.com`
   - Column 2: `https://www.apple.com/`
   - Column 3: `https://www.wikipedia.org/`
7. Save and show the three pages loading independently.
8. Open the sample workspace again, then choose **Open Configured Pages** to
   demonstrate that the sample did not overwrite the saved URLs.
9. Quit TriColumns from its application menu.

## Automated Camera Flow

For an externally filmed, repeatable flow, close unrelated windows, start the
iPhone recording on the macOS desktop, and then run:

```sh
osascript scripts/app_review_demo.applescript
```

The script quits any running copy, visibly launches `/Applications/TriColumns.app`,
opens the sample workspace, resizes the window, opens and closes Settings without
changing saved URLs, and leaves the fictional sample workspace visible. Reload
or navigate within a column manually if that interaction should also appear in
the recording. Grant macOS Accessibility permission to the terminal app running
`osascript` if prompted before the actual recording; that permission is for the
recording controller, not TriColumns.

## Permission Statement

Build 2 does not request camera, microphone, location, contacts, tracking, or
automation access, so there is no sensitive-data permission prompt to include.
The standard Open/Save panels may be shown if file upload/download behavior is
also demonstrated; use only a non-sensitive sample file.

## Before Uploading the Video

- Confirm text is readable and no real website account or personal timeline is
  visible.
- Host the video at a reviewer-accessible HTTPS URL that does not require an
  account, request access, or expire during review.
- Insert the final URL in `docs/APP_REVIEW_RESPONSE_2.1.md` and App Store Connect
  App Review Information > Notes.
