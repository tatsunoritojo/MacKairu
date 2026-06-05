#!/bin/bash
# MacKairu をビルドして .app バンドルを作る（SwiftPM）。
set -euo pipefail
cd "$(dirname "$0")"

APP="Kairu"
BUNDLE="$APP.app"
BIN_DIR="$BUNDLE/Contents/MacOS"
RES_DIR="$BUNDLE/Contents/Resources"

echo "==> swift build (release)"
swift build -c release --product "$APP"
BIN_PATH="$(swift build -c release --product "$APP" --show-bin-path)/$APP"

echo "==> .app バンドルを作成"
rm -rf "$BUNDLE"
mkdir -p "$BIN_DIR" "$RES_DIR"
cp "$BIN_PATH" "$BIN_DIR/$APP"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP</string>
    <key>CFBundleDisplayName</key>     <string>MacKairu</string>
    <key>CFBundleIdentifier</key>      <string>com.tatsu.kairu</string>
    <key>CFBundleVersion</key>         <string>1.0</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>$APP</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

echo "==> 署名（ローカル ad-hoc）"
codesign --force --deep --sign - "$BUNDLE" 2>/dev/null || echo "（codesign スキップ）"

echo "==> 完了: $(pwd)/$BUNDLE"
echo "起動: open \"$BUNDLE\""
