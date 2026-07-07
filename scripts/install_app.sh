#!/bin/sh
set -eu

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="$PROJECT_DIR/.xcode-derived"
APP_NAME="Pseudo-tweetdeck"
SCHEME_NAME="PseudoTweetDeck"
BUILT_BIN="$DERIVED_DATA_PATH/Build/Products/Release/$SCHEME_NAME"
APP_STAGING="$DERIVED_DATA_PATH/$APP_NAME.app"
INSTALL_PATH="/Applications/$APP_NAME.app"

xcodebuild \
  -scheme "$SCHEME_NAME" \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

rm -rf "$APP_STAGING"
mkdir -p "$APP_STAGING/Contents/MacOS"
cp "$PROJECT_DIR/AppBundle/Info.plist" "$APP_STAGING/Contents/Info.plist"
cp "$BUILT_BIN" "$APP_STAGING/Contents/MacOS/$APP_NAME"
chmod 755 "$APP_STAGING/Contents/MacOS/$APP_NAME"

codesign --force --deep --sign - "$APP_STAGING"

rm -rf "$INSTALL_PATH"
ditto "$APP_STAGING" "$INSTALL_PATH"
codesign --verify --deep --strict "$INSTALL_PATH"

echo "Installed $INSTALL_PATH"
