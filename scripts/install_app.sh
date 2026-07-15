#!/bin/sh
set -eu

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="$PROJECT_DIR/.xcode-derived"
APP_NAME="TriColumns"
SCHEME_NAME="TriColumns"
BUILT_APP="$DERIVED_DATA_PATH/Build/Products/Release/$APP_NAME.app"
INSTALL_PATH="/Applications/$APP_NAME.app"

xcodegen generate --spec "$PROJECT_DIR/project.yml" --project "$PROJECT_DIR"

xcodebuild \
  -project "$PROJECT_DIR/TriColumns.xcodeproj" \
  -scheme "$SCHEME_NAME" \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

rm -rf "$INSTALL_PATH"
ditto "$BUILT_APP" "$INSTALL_PATH"
codesign --verify --deep --strict "$INSTALL_PATH"

echo "Installed $INSTALL_PATH"
