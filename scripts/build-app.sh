#!/bin/bash
# TemizMac.app paketini derler. Gereksinim: Xcode veya Command Line Tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")/.."

# Gizlilik kontrolü: kaynak kodda ağ API'si varsa derlemeyi durdur.
if grep -rnE 'URLSession|NWConnection|CFNetwork|URLRequest|Network\.framework|import Network|socket\(' Sources/; then
  echo "HATA: Kaynak kodda ağ çağrısı bulundu. TemizMac ağa çıkmamalı." >&2; exit 1
fi

swift build -c release --arch arm64 --arch x86_64 2>/dev/null || swift build -c release
BIN="$(swift build -c release --show-bin-path)/TemizMac"
[ -f "$BIN" ] || BIN=".build/apple/Products/Release/TemizMac"

APP="build/TemizMac.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TemizMac"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
echo "Hazır: $APP  (çalıştır: open $APP)"
