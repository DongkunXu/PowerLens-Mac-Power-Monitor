#!/bin/zsh
# Builds the app and packages it for a GitHub release:
#   build/PowerLens-<version>.zip and build/PowerLens-<version>.zip.sha256
# The version comes from CFBundleShortVersionString in Resources/Info.plist.
set -euo pipefail
ROOT="${0:A:h:h}"

"$ROOT/scripts/build-app.sh"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
ZIP="$ROOT/build/PowerLens-$VERSION.zip"
rm -f "$ZIP" "$ZIP.sha256"

# ditto keeps the code signature and extended attributes intact (plain zip can break the bundle).
ditto -c -k --sequesterRsrc --keepParent "$ROOT/build/PowerLens.app" "$ZIP"
(cd "$ROOT/build" && shasum -a 256 "${ZIP:t}" > "${ZIP:t}.sha256")

echo "Packaged $ZIP"
cat "$ZIP.sha256"
