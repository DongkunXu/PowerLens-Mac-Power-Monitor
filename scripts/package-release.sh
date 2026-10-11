#!/bin/zsh
# Builds a signed, notarized release for GitHub:
#   build/PowerLens-<version>.zip and build/PowerLens-<version>.zip.sha256
# The version comes from CFBundleShortVersionString in Resources/Info.plist.
#
# Needs the maintainer's Developer ID certificate and a notarytool keychain profile
# (App Store Connect API key). Override them with POWERLENS_SIGN_IDENTITY and
# POWERLENS_NOTARY_PROFILE. Local builds (scripts/build-app.sh) stay ad-hoc signed.
set -euo pipefail
source "${0:A:h}/_env.sh"

IDENTITY="${POWERLENS_SIGN_IDENTITY:-Developer ID Application: Dongkun Xu (MV9DS6B998)}"
PROFILE="${POWERLENS_NOTARY_PROFILE:-lucarne-notary}"

if ! security find-identity -v -p codesigning | grep -qF "\"$IDENTITY\""; then
    echo "Signing identity not found in the keychain: $IDENTITY" >&2
    exit 1
fi

"$ROOT/scripts/build-app.sh"
mkdir -p "$TMPDIR"   # build-app.sh removes the shared temp directory when it exits
APP="$STAGED_APP"
trap '_powerlens_remove_staged_app; _powerlens_cleanup_tmp' EXIT

# Developer ID signature with the hardened runtime and a secure timestamp (required for
# notarization). The bundle has a single executable and no nested code, so one pass covers it.
codesign --force --sign "$IDENTITY" --options runtime --timestamp "$APP"
codesign --verify --strict --deep --verbose=2 "$APP"
if codesign -d --entitlements - "$APP" 2>/dev/null | grep -q get-task-allow; then
    echo "The app carries get-task-allow; notarization would reject it." >&2
    exit 1
fi

# Notarize a temporary zip, staple the ticket to the app, then package the stapled app.
SUBMISSION="$TMPDIR/PowerLens-notarize.zip"
ditto -c -k --keepParent "$APP" "$SUBMISSION"
xcrun notarytool submit "$SUBMISSION" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
ZIP="$ROOT/build/PowerLens-$VERSION.zip"
rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --keepParent "$APP" "$ZIP"
(cd "$ROOT/build" && shasum -a 256 "${ZIP:t}" > "${ZIP:t}.sha256")

echo "Packaged $ZIP"
cat "$ZIP.sha256"
