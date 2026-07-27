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

# Signing: defaults to ad-hoc ("-"). For App Store / Developer ID builds, set:
#   SIGNING_IDENTITY="Apple Distribution: Your Name (TEAMID)"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

# Args: --install moves the built bundle to /Applications and launches it.
INSTALL=false
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=true ;;
        -h|--help)
            echo "Usage: $0 [--install]"
            echo "  --install  Quit any running Lurkr, move the bundle to /Applications, and launch it."
            exit 0
            ;;
        *) echo "Unknown arg: $arg" >&2; exit 1 ;;
    esac
done

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
  <key>CFBundleShortVersionString</key><string>1.0</string>
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
codesign \
    --force \
    --deep \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGNING_IDENTITY" \
    "$APP_DIR"

rm -rf "$BUILD_DIR"

echo ""
echo "✓ Built: $APP_DIR"

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
