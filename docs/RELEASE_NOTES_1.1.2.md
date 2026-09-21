# TriColumns 1.1.2 (8)

## 日本語

・カラムの操作ボタンとURL欄を見やすく整理しました。
・移動メニューと、カラム選択・URL入力・再読み込みなどのキーボードショートカットを追加しました。
・空欄のカラムに、Webサイトを開くための案内を追加しました。
・設定画面の説明と配置を改善し、Tabキーでの移動や入力エラー後の操作を修正しました。
・操作ボタンとURL欄のアクセシビリティラベルを改善しました。

## English

• Refined column controls and address fields for better readability.
• Added a Navigate menu and keyboard shortcuts for choosing columns, entering addresses, reloading, and browsing history.
• Added guidance for opening a website in an empty column.
• Improved Settings layout, keyboard navigation, and focus after an invalid address.
• Improved accessibility labels for navigation controls and address fields.

## Review notes

TriColumns is a native three-column WebKit browser for macOS 14 and later.
Version 1.1.2 (build 8) improves the native column controls, address-field
readability, empty-column guidance and Settings layout. The Navigate menu adds
Command-1/2/3 to select column addresses, Command-L for the current address,
Command-R to reload, and Command-[ / Command-] for history. Settings supports
Tab/Shift-Tab, Return to save, Escape to cancel, and focus restoration after
invalid input.

Review without an account: choose TriColumns > Open Sample Workspace. Three
bundled fictional pages demonstrate the layout offline without changing saved
URLs. Choose Open Configured Pages to return to the saved configuration. Each
column supports native navigation, an address field, uploads, downloads, and
JavaScript dialogs. Privacy Policy and Support links are available in the
TriColumns menu.

HTTP browsing justification: NSAllowsArbitraryLoadsInWebContent is enabled
because users can enter arbitrary HTTP or HTTPS destinations in this
general-purpose browser. HTTPS is the default for addresses without a scheme.
HTTP addresses are displayed in orange with an unencrypted-connection warning.
The exception is limited to WebKit web content; certificate validation is not
bypassed.

TriColumns has no developer-operated account system, analytics, advertising,
tracking, in-app purchases, or subscriptions. Website accounts and data handling
are controlled by the websites themselves. TriColumns does not use X APIs,
scrape content, automate engagement, or share Safari cookies. It is not
affiliated with X Corp.

Sandbox: outbound networking loads user-configured websites; user-selected
read/write access supports uploads and downloads.
