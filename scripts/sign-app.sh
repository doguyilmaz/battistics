#!/bin/bash
# Re-signs Sparkle's nested components with our Developer ID, inside out,
# then the app itself. Needed because CLI (non-archive) builds keep
# Sparkle's own distribution signature on its nested apps and XPC services,
# which notarization rejects.
set -euo pipefail

APP="${1:?usage: sign-app.sh <path-to.app>}"
IDENTITY="${SIGN_IDENTITY:-"-"}"

# Real identities get hardened runtime + timestamp (required for
# notarization). Ad-hoc local builds get neither: hardened runtime's
# library validation treats a team-less binary as matching no team, which
# would block loading the equally team-less Sparkle framework.
FLAGS=(-f -s "$IDENTITY")
if [ "$IDENTITY" != "-" ]; then
    FLAGS+=(-o runtime --timestamp)
fi

SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"

if [ -d "$SPARKLE" ]; then
    codesign "${FLAGS[@]}" --preserve-metadata=entitlements \
        "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
    codesign "${FLAGS[@]}" "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
    codesign "${FLAGS[@]}" "$SPARKLE/Versions/B/Autoupdate"
    codesign "${FLAGS[@]}" "$SPARKLE/Versions/B/Updater.app"
    codesign "${FLAGS[@]}" "$SPARKLE"
fi

codesign "${FLAGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
echo "Signed $APP with $IDENTITY"
