#!/bin/zsh
# Removes every build product of this project (the installed app is untouched).
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if [[ -d build ]]; then
    find build -maxdepth 3 -name '*.app' -type d -exec "$LSREGISTER" -u {} \; 2>/dev/null || true
fi
rm -rf "$ROOT/.build" "$ROOT/build"
echo "Removed .build/ and build/"
