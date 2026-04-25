#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

VERSION="1.0.1"
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
[ -f "$DIR/Veil.icns" ] && cp "$DIR/Veil.icns" "$APP/Contents/Resources/Veil.icns"

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
  <key>CFBundleIconFile</key><string>Veil</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Veil needs the microphone to transcribe audio with Whisper.</string>
  <key>NSScreenCaptureUsageDescription</key><string>Veil needs screen access to capture context for AI responses.</string>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key><true/>
  </dict>
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
  --identifier "com.local.veil" \
  --entitlements /tmp/entitlements.plist \
  "$APP"

echo "→ Resetting TCC permissions (signature changed)..."
tccutil reset ScreenCapture com.local.veil 2>/dev/null || true
tccutil reset Microphone    com.local.veil 2>/dev/null || true

echo "→ Creating DMG..."
STAGING="$(mktemp -d)/Veil"
mkdir -p "$STAGING"
cp -r "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Create writable DMG, mount, set volume icon, unmount, convert
TMP_DMG="$DIR/tmp_veil.dmg"
rm -f "$TMP_DMG" "$DMG"
hdiutil create -volname "Veil" -srcfolder "$STAGING" -ov -format UDRW "$TMP_DMG" > /dev/null

MOUNT_DIR="$(mktemp -d)"
hdiutil attach "$TMP_DMG" -mountpoint "$MOUNT_DIR" -nobrowse -quiet

[ -f "$DIR/Veil.icns" ] && cp "$DIR/Veil.icns" "$MOUNT_DIR/.VolumeIcon.icns"

# Set custom icon flag on the volume
python3 - "$MOUNT_DIR" << 'PYEOF'
import subprocess, sys
path = sys.argv[1]
try:
    r = subprocess.run(['xattr', '-px', 'com.apple.FinderInfo', path], capture_output=True, text=True)
    d = bytearray.fromhex(r.stdout.replace(' ','').replace('\n','')) if r.returncode == 0 else bytearray(32)
    if len(d) < 32: d += bytearray(32 - len(d))
    d[8] |= 0x04  # kHasCustomIcon
    subprocess.run(['xattr', '-wx', 'com.apple.FinderInfo', d.hex(), path], check=True)
except Exception as e:
    print(f"  icon flag warning: {e}")
PYEOF

hdiutil detach "$MOUNT_DIR" -quiet
hdiutil convert "$TMP_DMG" -format UDZO -o "$DMG" > /dev/null
rm -f "$TMP_DMG"
rm -rf "$STAGING"

echo ""
echo "✓ Done:"
echo "  App:  $DIR/$APP"
echo "  DMG:  $DIR/$DMG"
echo ""
echo "→ To run: "   
echo "    open $DIR/$APP"
echo "→ To install: "
echo "    open $DIR/$DMG  (drag Veil to Applications)"
echo ""
echo "→ To release on GitHub:"
echo "  git tag v${VERSION} && git push origin main --tags"
echo "  # Then upload $DMG to the GitHub release"
