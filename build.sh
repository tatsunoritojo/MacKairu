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

# 画像アセット（裏キャラ等）をバンドルへ。
if [ -d Resources ]; then cp -R Resources/. "$RES_DIR/"; fi

# アプリアイコン（assets/appicon.png → AppIcon.icns）を生成。
ICON_SRC="assets/appicon.png"
HAS_ICON=0
if [ -f "$ICON_SRC" ]; then
    echo "==> アプリアイコンを生成"
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    # (基準サイズ, 出力ピクセル, @2xか) の標準セット。
    make() { sips -z "$2" "$2" "$ICON_SRC" --out "$ICONSET/$1" >/dev/null; }
    make icon_16x16.png 16;      make icon_16x16@2x.png 32
    make icon_32x32.png 32;      make icon_32x32@2x.png 64
    make icon_128x128.png 128;   make icon_128x128@2x.png 256
    make icon_256x256.png 256;   make icon_256x256@2x.png 512
    make icon_512x512.png 512;   make icon_512x512@2x.png 1024
    iconutil -c icns "$ICONSET" -o "$RES_DIR/AppIcon.icns" && HAS_ICON=1
fi

ICON_PLIST=""
if [ "$HAS_ICON" = "1" ]; then
    ICON_PLIST="    <key>CFBundleIconFile</key>        <string>AppIcon</string>"
fi

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
$ICON_PLIST
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
