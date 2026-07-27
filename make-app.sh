#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Lurkr"
EXEC_NAME="Lurkr"
BUNDLE_ID="com.singlepeel.lurkr"
APP_DIR="$PROJECT_DIR/$APP_NAME.app"
INSTALLED_APP="/Applications/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
BUILD_DIR="$PROJECT_DIR/build"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
ENTITLEMENTS="$PROJECT_DIR/Lurkr.entitlements"
PRIVACY_MANIFEST="$PROJECT_DIR/PrivacyInfo.xcprivacy"
VERSION="1.0.0"

# Signing: defaults to ad-hoc ("-"). For App Store / Developer ID builds, set:
#   SIGNING_IDENTITY="Apple Distribution: Your Name (TEAMID)"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

# Keychain profile holding notarization credentials, created once via:
#   xcrun notarytool store-credentials
NOTARY_PROFILE="${NOTARY_PROFILE:-lurkr-notary}"

# Args: --install moves the built bundle to /Applications and launches it.
INSTALL=false
DIST=false
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=true ;;
        --dist) DIST=true ;;
        -h|--help)
            echo "Usage: $0 [--install] [--dist]"
            echo "  --install  Quit any running Lurkr, move the bundle to /Applications, and launch it."
            echo "  --dist     Notarize, staple, and produce a distributable zip."
            echo "             Requires SIGNING_IDENTITY set to a Developer ID Application cert."
            exit 0
            ;;
        *) echo "Unknown arg: $arg" >&2; exit 1 ;;
    esac
done

if [ "$DIST" = true ] && [ "$SIGNING_IDENTITY" = "-" ]; then
    echo "Error: --dist cannot notarize an ad-hoc signature." >&2
    echo "Set a Developer ID identity first, e.g.:" >&2
    echo "  SIGNING_IDENTITY=\"Developer ID Application: Scott Foster (8PML37YH4W)\" $0 --dist" >&2
    echo "Available identities:" >&2
    security find-identity -v -p codesigning >&2
    exit 1
fi

echo "→ Building release binary"
cd "$PROJECT_DIR"
swift build -c release

echo "→ Rendering app icons"
rm -rf "$BUILD_DIR"
mkdir -p "$ICONSET_DIR"
swift "$PROJECT_DIR/Tools/render_icons.swift" "$ICONSET_DIR"

echo "→ Assembling .app"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp ".build/release/$EXEC_NAME" "$CONTENTS/MacOS/$EXEC_NAME"
iconutil -c icns "$ICONSET_DIR" -o "$CONTENTS/Resources/AppIcon.icns"

if [ -f "$PRIVACY_MANIFEST" ]; then
    cp "$PRIVACY_MANIFEST" "$CONTENTS/Resources/PrivacyInfo.xcprivacy"
fi

cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$EXEC_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Singlepeel</string>
</dict>
</plist>
EOF

echo "→ Code signing ($SIGNING_IDENTITY)"
CODESIGN_ARGS=(
    --force
    --deep
    --options runtime
    --entitlements "$ENTITLEMENTS"
    --sign "$SIGNING_IDENTITY"
)
# Notarization requires a secure timestamp, which an ad-hoc signature cannot carry.
if [ "$SIGNING_IDENTITY" != "-" ]; then
    CODESIGN_ARGS+=(--timestamp)
fi
codesign "${CODESIGN_ARGS[@]}" "$APP_DIR"

rm -rf "$BUILD_DIR"

echo ""
echo "✓ Built: $APP_DIR"

if [ "$DIST" = true ]; then
    ZIP_PATH="$PROJECT_DIR/$APP_NAME-$VERSION-arm64.zip"

    echo ""
    echo "→ Zipping for notarization"
    rm -f "$ZIP_PATH"
    ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

    echo "→ Submitting to Apple (usually a few minutes)"
    xcrun notarytool submit "$ZIP_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    echo "→ Stapling ticket"
    xcrun stapler staple "$APP_DIR"

    # Stapling writes the ticket into the bundle, so the shipped zip must be
    # rebuilt from the stapled copy — the pre-staple zip is not notarized on disk.
    echo "→ Rebuilding zip from stapled bundle"
    rm -f "$ZIP_PATH"
    ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

    echo "→ Verifying Gatekeeper acceptance"
    xcrun stapler validate "$APP_DIR"
    spctl -a -vvv -t install "$APP_DIR"

    echo ""
    echo "✓ Notarized and stapled: $ZIP_PATH"
fi

if [ "$INSTALL" = true ]; then
    echo ""
    echo "→ Stopping any running Lurkr"
    pkill -x "$EXEC_NAME" 2>/dev/null || true
    sleep 0.5

    echo "→ Installing to /Applications"
    rm -rf "$INSTALLED_APP"
    mv "$APP_DIR" "$INSTALLED_APP"

    echo "→ Launching"
    open "$INSTALLED_APP"

    echo ""
    echo "✓ Installed and running: $INSTALLED_APP"
else
    echo ""
    echo "Install manually:"
    echo "  pkill -x $EXEC_NAME; mv \"$APP_DIR\" /Applications/"
    echo ""
    echo "Or run with --install to do that automatically:"
    echo "  ./make-app.sh --install"
fi
