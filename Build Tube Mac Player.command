#!/bin/bash
# Double-click this file to turn the project into "Tube Mac Player.app".
set -e
cd "$(dirname "$0")"
clear
echo "▶︎ Tube Mac Player builder"
echo

if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Your Mac needs Apple's free command line tools first (one time only)."
  echo "A window will pop up — click Install. When it's done, double-click this file again."
  xcode-select --install 2>/dev/null || true
  read -n 1 -s -r -p "Press any key to close…"
  exit 0
fi

echo "Building… (the first time takes a minute or two)"
swift build -c release

APP="Tube Mac Player.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/TubeMacPlayer" "$APP/Contents/MacOS/TubeMacPlayer"
cp Info.plist "$APP/Contents/Info.plist"
cp Logo.png "$APP/Contents/Resources/Logo.png"

# Your own icon: drop a file called AppIcon.png (1024×1024) or AppIcon.icns next to this script.
if [ -f AppIcon.icns ]; then
  cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
elif [ -f AppIcon.png ]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

# Put it in Applications
rm -rf "/Applications/$APP" 2>/dev/null || true
if cp -R "$APP" /Applications/ 2>/dev/null; then
  echo; echo "✅ Done! Tube Mac Player is in your Applications folder."
  open "/Applications/$APP"
else
  echo; echo "✅ Done! Tube Mac Player.app is in this folder."
  open "$APP"
fi
