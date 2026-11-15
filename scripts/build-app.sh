#!/bin/bash
# Cleanstone.app paketini derler. Gereksinim: Xcode veya Command Line Tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")/.."

# Gizlilik kontrolü: kaynak kodda ağ API'si varsa derlemeyi durdur.
if grep -rnE 'URLSession|NWConnection|CFNetwork|URLRequest|Network\.framework|import Network|socket\(' Sources/; then
  echo "HATA: Kaynak kodda ağ çağrısı bulundu. Cleanstone ağa çıkmamalı." >&2; exit 1
fi

swift build -c release --arch arm64 --arch x86_64 2>/dev/null || swift build -c release
BIN="$(swift build -c release --show-bin-path)/Cleanstone"
[ -f "$BIN" ] || BIN=".build/apple/Products/Release/Cleanstone"

APP="build/Cleanstone.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Cleanstone"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Uygulama ikonu: 1024 PNG'den .icns üret
ICONSET="build/AppIcon.iconset"; rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz Resources/Icon/icon_1024.png --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
  d=$((sz*2)); sips -z $d $d Resources/Icon/icon_1024.png --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
echo "Hazır: $APP  (çalıştır: open $APP)"
