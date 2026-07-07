# PseudoTweetDeck

macOS native prototype that shows three x.com views in one window using WebKit (`WKWebView`).

## Run

```sh
swift run PseudoTweetDeck
```

## Install App

Build with Xcode and install as `/Applications/Pseudo-tweetdeck.app`:

```sh
scripts/install_app.sh
```

By default, each column reloads every 5 minutes. To change the interval, set seconds with:

```sh
PSEUDO_TWEETDECK_RELOAD_SECONDS=120 swift run PseudoTweetDeck
```

To disable automatic reload:

```sh
PSEUDO_TWEETDECK_RELOAD_SECONDS=0 swift run PseudoTweetDeck
```

By default, `WKWebView` uses its current WebKit/macOS user agent instead of a hard-coded string. To override it:

```sh
PSEUDO_TWEETDECK_USER_AGENT="Mozilla/5.0 ..." swift run PseudoTweetDeck
```

The default columns are:

- `https://x.com/lists/94145057`
- `https://x.com/notifications`
- `https://x.com/home`

This does not embed Safari itself. It uses the same WebKit engine family through `WKWebView`. Cookies are shared between the three panes inside this app, but they are not Safari's normal browser cookies, so the first launch may require signing in to x.com.

## Notes

- A plain web app with three `iframe` panes is not a good fit because x.com prevents being embedded by other sites.
- A Chrome-based version is possible with Electron, using separate web contents in one window.
- Safari App Extensions cannot freely compose multiple Safari pages into one custom window.
