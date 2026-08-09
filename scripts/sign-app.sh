#!/bin/bash
# Re-signs Sparkle's nested components with our Developer ID, inside out,
# then the app itself. Needed because CLI (non-archive) builds keep
# Sparkle's own distribution signature on its nested apps and XPC services,
# which notarization rejects.
set -euo pipefail

APP="${1:?usage: sign-app.sh <path-to.app>}"
IDENTITY="${SIGN_IDENTITY:?SIGN_IDENTITY must be set to a Developer ID identity}"

SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"

if [ -d "$SPARKLE" ]; then
    codesign -f -s "$IDENTITY" -o runtime --timestamp --preserve-metadata=entitlements \
        "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
    codesign -f -s "$IDENTITY" -o runtime --timestamp \
        "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
    codesign -f -s "$IDENTITY" -o runtime --timestamp \
        "$SPARKLE/Versions/B/Autoupdate"
    codesign -f -s "$IDENTITY" -o runtime --timestamp \
        "$SPARKLE/Versions/B/Updater.app"
    codesign -f -s "$IDENTITY" -o runtime --timestamp "$SPARKLE"
fi

codesign -f -s "$IDENTITY" -o runtime --timestamp "$APP"
codesign --verify --deep --strict "$APP"
echo "Signed $APP with $IDENTITY"
