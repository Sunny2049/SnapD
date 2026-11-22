#!/bin/bash
set -e
cd "$(dirname "$0")"
echo "==> Building SnapD (release)…"
swift build -c release
BIN=".build/release/SnapD"
APP="SnapD.app"
echo "==> Assembling $APP …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SnapD"
cp Info.plist "$APP/Contents/Info.plist"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Signing: prefer a stable self-signed identity named "SnapD Signing" if one
# exists — macOS ties the Screen Recording (TCC) grant to the code signature,
# so a stable identity keeps the grant across rebuilds. Without it, fall back
# to ad-hoc signing (works, but macOS may ask you to re-grant Screen Recording
# after each rebuild).
# Optional: if that identity lives in a dedicated keychain at
# ~/Library/Keychains/snapd.keychain-db, put its password in
# ~/.snapd-keychain-password (a local file, never committed) and it will be
# unlocked before signing.
if [ -f ~/Library/Keychains/snapd.keychain-db ] && [ -f ~/.snapd-keychain-password ]; then
  security unlock-keychain -p "$(cat ~/.snapd-keychain-password)" ~/Library/Keychains/snapd.keychain-db 2>/dev/null || true
fi
if security find-identity -v -p codesigning 2>/dev/null | grep -q "SnapD Signing"; then
  codesign --force --deep --sign "SnapD Signing" "$APP" && echo "==> Signed with stable identity: SnapD Signing"
else
  codesign --force --deep --sign - "$APP" 2>/dev/null || echo "Note: codesign failed; the app still runs, but you may need to re-grant Screen Recording after rebuilds."
fi
echo "==> Done: $APP"
echo "Install:  cp -R SnapD.app /Applications/"
echo "Run:      open SnapD.app"
