#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

VERSION="1.0.0"
APP="Veil.app"
DMG="Veil-v${VERSION}.dmg"

echo "→ Building Veil..."
swift build -c release 2>&1

BINARY=".build/release/Veil"

echo "→ Creating .app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/Veil"

cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Veil</string>
  <key>CFBundleIdentifier</key><string>com.local.veil</string>
  <key>CFBundleName</key><string>Veil</string>
  <key>CFBundleVersion</key><string>1.0.0</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Veil needs the microphone to transcribe audio with Whisper.</string>
</dict>
</plist>
PLIST

echo "→ Signing..."
cat > /tmp/entitlements.plist << 'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><false/>
</dict>
</plist>
ENT

codesign --force --deep --sign - \
  --entitlements /tmp/entitlements.plist \
  "$APP"

echo "→ Creating DMG..."
STAGING="$(mktemp -d)/Veil"
mkdir -p "$STAGING"
cp -r "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create \
  -volname "Veil" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG"

rm -rf "$STAGING"

echo ""
echo "✓ Done:"
echo "  App:  $DIR/$APP"
echo "  DMG:  $DIR/$DMG"
echo ""
echo "→ To run:    open $DIR/$APP"
echo "→ To install: open $DIR/$DMG  (drag Veil to Applications)"
echo ""
echo "→ To release on GitHub:"
echo "  git tag v${VERSION} && git push origin main --tags"
echo "  # Then upload $DMG to the GitHub release"
