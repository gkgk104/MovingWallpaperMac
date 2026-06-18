#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MotionDock"
BINARY_NAME="MovingWallpaperMac"
BUNDLE_EXECUTABLE="$APP_NAME"
ICON_NAME="MotionDock"
APP_ICONSET="$ROOT_DIR/Sources/MovingWallpaperMac/Resources/Assets.xcassets/AppIcon.appiconset"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/motiondock-build.XXXXXX")"
TMP_APP_DIR="$TMP_ROOT/$APP_NAME.app"
PLIST="$TMP_APP_DIR/Contents/Info.plist"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

cd "$ROOT_DIR"
swift build -c release --product "$BINARY_NAME"

rm -rf "$TMP_APP_DIR"
mkdir -p "$TMP_APP_DIR/Contents/MacOS" "$TMP_APP_DIR/Contents/Resources"
cp ".build/release/$BINARY_NAME" "$TMP_APP_DIR/Contents/MacOS/$BUNDLE_EXECUTABLE"
if [[ -d "$APP_ICONSET" ]] && command -v iconutil >/dev/null 2>&1; then
  ICONSET="$TMP_ROOT/$ICON_NAME.iconset"
  mkdir -p "$ICONSET"
  cp "$APP_ICONSET"/icon_*.png "$ICONSET"/
  iconutil -c icns -o "$TMP_ROOT/$ICON_NAME.icns" "$ICONSET"
  cp "$TMP_ROOT/$ICON_NAME.icns" "$TMP_APP_DIR/Contents/Resources/$ICON_NAME.icns"
fi

RESOURCE_BUNDLE="$(find "$ROOT_DIR/.build" -path '*/release/MovingWallpaperMac_MovingWallpaperMac.bundle' -type d -print -quit)"
if [[ -n "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$TMP_APP_DIR/Contents/Resources/"
fi

/usr/bin/plutil -create xml1 "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $APP_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string local.codex.motiondock" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $BUNDLE_EXECUTABLE" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string $ICON_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.0" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :LSMultipleInstancesProhibited bool true" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 13.0" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$PLIST"

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$TMP_APP_DIR" 2>/dev/null || true
  find "$TMP_APP_DIR" -exec xattr -c {} + 2>/dev/null || true
  xattr -c "$TMP_APP_DIR" 2>/dev/null || true
  xattr -d com.apple.FinderInfo "$TMP_APP_DIR" 2>/dev/null || true
fi

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$TMP_APP_DIR" >/dev/null
fi

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$TMP_APP_DIR" 2>/dev/null || true
  xattr -d com.apple.FinderInfo "$TMP_APP_DIR" 2>/dev/null || true
fi

rm -rf "$APP_DIR"
mkdir -p "$(dirname "$APP_DIR")"
if command -v ditto >/dev/null 2>&1; then
  ditto --noextattr --noqtn "$TMP_APP_DIR" "$APP_DIR"
else
  cp -R "$TMP_APP_DIR" "$APP_DIR"
fi

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$APP_DIR" 2>/dev/null || true
  find "$APP_DIR" -exec xattr -c {} + 2>/dev/null || true
  xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
fi

echo "$APP_DIR"
