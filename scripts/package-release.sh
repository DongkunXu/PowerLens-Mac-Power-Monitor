#!/bin/zsh
# Builds the app and packages it for a GitHub release:
#   build/PowerLens-<version>.zip and build/PowerLens-<version>.zip.sha256
# The version comes from CFBundleShortVersionString in Resources/Info.plist.
set -euo pipefail
source "${0:A:h}/_env.sh"

"$ROOT/scripts/build-app.sh"
mkdir -p "$TMPDIR"   # build-app.sh removes the shared temp directory when it exits

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
ZIP="$ROOT/build/PowerLens-$VERSION.zip"
rm -f "$ZIP" "$ZIP.sha256"

# ditto keeps the code signature and extended attributes intact (plain zip can break the bundle).
ditto -c -k --sequesterRsrc --keepParent "$STAGED_APP" "$ZIP"
(cd "$ROOT/build" && shasum -a 256 "${ZIP:t}" > "${ZIP:t}.sha256")
_powerlens_remove_staged_app

echo "Packaged $ZIP"
cat "$ZIP.sha256"
