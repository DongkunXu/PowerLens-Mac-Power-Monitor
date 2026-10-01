#!/bin/zsh
# Regenerates Resources/AppIcon.icns and the README logo (docs/images/icon.png)
# from tools/icon/make_icon.swift. Only needed after changing the icon design.
set -euo pipefail
source "${0:A:h}/_env.sh"

OUT="$ROOT/.build/icon"
mkdir -p "$OUT"
swiftc -O "$ROOT/tools/icon/make_icon.swift" -o "$OUT/make_icon" -module-cache-path "$TMPDIR/module-cache"

ICONSET="$TMPDIR/AppIcon.iconset"
"$OUT/make_icon" "$ICONSET" "$ROOT/docs/images/icon.png"
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
echo "Wrote Resources/AppIcon.icns and docs/images/icon.png"
