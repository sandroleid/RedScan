#!/bin/zsh
# Baut RedScan.app (Release) – benötigt nur die Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/RedScan.app"

echo "▶ Kompiliere (Release) …"
swift build -c release

# Icon einmalig erzeugen
if [[ ! -f Resources/AppIcon.icns ]]; then
  echo "▶ Erzeuge App-Icon …"
  TMP=$(mktemp -d)
  swift Tools/make_icon.swift "$TMP/icon_1024.png"
  ICONSET="$TMP/AppIcon.iconset"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$TMP/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
  rm -rf "$TMP"
fi

echo "▶ Erzeuge App-Bundle …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/RedScan "$APP/Contents/MacOS/RedScan"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/oui.txt "$APP/Contents/Resources/oui.txt"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "▶ Signiere (ad-hoc) …"
codesign --force --sign - "$APP"

echo "✅ Fertig: $(pwd)/$APP"
echo "   Starten mit: open \"$APP\"   (oder nach /Applications kopieren)"
