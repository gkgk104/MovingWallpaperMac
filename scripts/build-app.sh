#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MotionDock"
BINARY_NAME="MovingWallpaperMac"
BUNDLE_EXECUTABLE="$APP_NAME"
BUNDLE_IDENTIFIER="${MOTIONDOCK_BUNDLE_IDENTIFIER:-com.motiondock.app}"
VERSION="${MOTIONDOCK_VERSION:-1.0}"
BUILD_NUMBER="${MOTIONDOCK_BUILD_NUMBER:-1}"
ICON_NAME="MotionDock"
APP_ICONSET="$ROOT_DIR/Sources/MovingWallpaperMac/Resources/Assets.xcassets/AppIcon.appiconset"
ENTITLEMENTS_FILE="$ROOT_DIR/scripts/MotionDock.entitlements"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
ZIP_PATH="$ROOT_DIR/dist/$APP_NAME.zip"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/motiondock-build.XXXXXX")"
TMP_APP_DIR="$TMP_ROOT/$APP_NAME.app"
PLIST="$TMP_APP_DIR/Contents/Info.plist"
SIGN_IDENTITY="${MOTIONDOCK_SIGN_IDENTITY:--}"
ENABLE_HARDENED_RUNTIME="${MOTIONDOCK_HARDENED_RUNTIME:-1}"
INCLUDE_RESTRICTED_ENTITLEMENTS="${MOTIONDOCK_INCLUDE_RESTRICTED_ENTITLEMENTS:-auto}"
ENABLE_NOTARIZATION="${MOTIONDOCK_NOTARIZE:-0}"
VERIFY_GATEKEEPER="${MOTIONDOCK_VERIFY_SPCTL:-0}"

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
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_IDENTIFIER" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $BUNDLE_EXECUTABLE" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string $ICON_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :LSMultipleInstancesProhibited bool true" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 13.0" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0 dict" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLName string $BUNDLE_IDENTIFIER" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string motiondock" "$PLIST"

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$TMP_APP_DIR" 2>/dev/null || true
  find "$TMP_APP_DIR" -exec xattr -c {} + 2>/dev/null || true
  xattr -c "$TMP_APP_DIR" 2>/dev/null || true
  xattr -d com.apple.FinderInfo "$TMP_APP_DIR" 2>/dev/null || true
fi

if command -v codesign >/dev/null 2>&1; then
  CODESIGN_ARGS=(--force --deep --sign "$SIGN_IDENTITY")
  if [[ "$ENABLE_HARDENED_RUNTIME" == "1" ]]; then
    CODESIGN_ARGS+=(--options runtime)
  fi
  if [[ -f "$ENTITLEMENTS_FILE" ]]; then
    if [[ "$INCLUDE_RESTRICTED_ENTITLEMENTS" == "1" || ( "$INCLUDE_RESTRICTED_ENTITLEMENTS" == "auto" && "$SIGN_IDENTITY" != "-" ) ]]; then
      CODESIGN_ARGS+=(--entitlements "$ENTITLEMENTS_FILE")
    elif [[ "$INCLUDE_RESTRICTED_ENTITLEMENTS" == "auto" ]]; then
      echo "Skipping entitlements for ad-hoc local signing. Set MOTIONDOCK_SIGN_IDENTITY and MOTIONDOCK_INCLUDE_RESTRICTED_ENTITLEMENTS=1 if distribution entitlements are added." >&2
    fi
  fi
  codesign "${CODESIGN_ARGS[@]}" "$TMP_APP_DIR" >/dev/null
fi

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$TMP_APP_DIR" 2>/dev/null || true
  xattr -d com.apple.FinderInfo "$TMP_APP_DIR" 2>/dev/null || true
fi

rm -rf "$APP_DIR"
rm -f "$ZIP_PATH"
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

if command -v ditto >/dev/null 2>&1; then
  (cd "$(dirname "$APP_DIR")" && ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$ZIP_PATH")
else
  (cd "$(dirname "$APP_DIR")" && zip -qry "$ZIP_PATH" "$APP_NAME.app")
fi

if [[ "$ENABLE_NOTARIZATION" == "1" ]]; then
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "MOTIONDOCK_NOTARIZE=1 requires MOTIONDOCK_SIGN_IDENTITY to be a Developer ID Application certificate." >&2
    exit 1
  fi
  if ! command -v xcrun >/dev/null 2>&1; then
    echo "xcrun is required for notarization." >&2
    exit 1
  fi

  if [[ -n "${MOTIONDOCK_NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$MOTIONDOCK_NOTARY_PROFILE" --wait
  elif [[ -n "${MOTIONDOCK_APPLE_ID:-}" && -n "${MOTIONDOCK_TEAM_ID:-}" && -n "${MOTIONDOCK_APP_PASSWORD:-}" ]]; then
    xcrun notarytool submit "$ZIP_PATH" \
      --apple-id "$MOTIONDOCK_APPLE_ID" \
      --team-id "$MOTIONDOCK_TEAM_ID" \
      --password "$MOTIONDOCK_APP_PASSWORD" \
      --wait
  else
    echo "Set MOTIONDOCK_NOTARY_PROFILE or MOTIONDOCK_APPLE_ID, MOTIONDOCK_TEAM_ID, and MOTIONDOCK_APP_PASSWORD for notarization." >&2
    exit 1
  fi

  xcrun stapler staple "$APP_DIR"
  rm -f "$ZIP_PATH"
  if command -v ditto >/dev/null 2>&1; then
    (cd "$(dirname "$APP_DIR")" && ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$ZIP_PATH")
  else
    (cd "$(dirname "$APP_DIR")" && zip -qry "$ZIP_PATH" "$APP_NAME.app")
  fi
fi

if [[ "$VERIFY_GATEKEEPER" == "1" ]]; then
  spctl -a -vv --type execute "$APP_DIR"
fi

echo "$APP_DIR"
echo "$ZIP_PATH"
