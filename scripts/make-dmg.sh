#!/bin/bash
# Packages dist/Battistics.app into a compressed DMG with an /Applications
# shortcut. Signs the image when SIGN_IDENTITY is a real identity.
set -euo pipefail

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Sources/BattisticsApp/Support/Info.plist)
APP="dist/Battistics.app"
STAGE="dist/dmg-stage"
DMG="dist/Battistics-$VERSION.dmg"

[ -d "$APP" ] || { echo "error: $APP missing, run 'make app' first"; exit 1; }

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Battistics.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Battistics" -srcfolder "$STAGE" -ov -format UDZO \
    -imagekey zlib-level=9 "$DMG"
rm -rf "$STAGE"

if [ -n "${SIGN_IDENTITY:-}" ] && [ "$SIGN_IDENTITY" != "-" ]; then
    codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi

echo "Created $DMG"
