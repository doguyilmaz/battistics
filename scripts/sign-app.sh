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

for TOOL in BattisticsPowerHelper battistics-mcp; do
    if [ -f "$APP/Contents/MacOS/$TOOL" ]; then
        codesign "${FLAGS[@]}" "$APP/Contents/MacOS/$TOOL"
    fi
done
if [ -f "$APP/Contents/Helpers/battistics" ]; then
    codesign "${FLAGS[@]}" "$APP/Contents/Helpers/battistics"
fi
# A Developer ID profile is what lets a release use iCloud and push outside
# the App Store; without one the app keeps the base entitlements.
if [ -n "${PROFILE:-}" ]; then
    cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
    codesign "${FLAGS[@]}" --entitlements "$(dirname "$0")/../Sources/BattisticsApp/Support/Battistics-Release.entitlements" "$APP"
    # macOS refuses to launch an app whose profile does not list its signing certificate.
    python3 - "$PROFILE" "$APP" <<'PY'
import plistlib, subprocess, sys, tempfile
profile = plistlib.loads(subprocess.run(["security", "cms", "-D", "-i", sys.argv[1]], capture_output=True, check=True).stdout)
out = tempfile.mkdtemp() + "/cert"
subprocess.run(["codesign", "-d", f"--extract-certificates={out}", sys.argv[2]], capture_output=True, check=True)
if open(out + "0", "rb").read() not in profile["DeveloperCertificates"]:
    sys.exit("The provisioning profile does not list the certificate that signed the app.")
PY
else
    codesign "${FLAGS[@]}" --preserve-metadata=entitlements "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "Signed $APP with $IDENTITY"
