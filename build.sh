#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

echo "→ Compilando OllamaChat..."
swift build -c release 2>&1

BINARY=".build/release/OllamaChat"

echo "→ Creando .app bundle..."
APP="OllamaChat.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/OllamaChat"

cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>OllamaChat</string>
  <key>CFBundleIdentifier</key><string>com.local.ollamachat</string>
  <key>CFBundleName</key><string>OllamaChat</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "→ Firmando con entitlement screen-capture excluded..."
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

# Firmar ad-hoc (sin Apple Developer account)
codesign --force --deep --sign - \
  --entitlements /tmp/entitlements.plist \
  "$APP"

echo ""
echo "✓ Build completado: $DIR/$APP"
echo ""
echo "Para ejecutar:"
echo "  open $DIR/$APP"
echo ""
echo "Para que arranque al inicio:"
echo "  cp -r $DIR/$APP /Applications/"
echo "  # Añadir a Inicio de Sesión en Ajustes del Sistema"
