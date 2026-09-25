#!/bin/zsh
# Renders the real panel with live data into .build/snapshots/ (light and dark).
#   scripts/snapshot.sh [extra powerlens-snapshot args, e.g. --language zh-Hans --expand 2 --range 5 --seconds 40]
# Output: panel[-<language>]-light.png and panel[-<language>]-dark.png
set -euo pipefail
source "${0:A:h}/_env.sh"

SUFFIX=""
if (( ${@[(Ie)--language]} )); then
    SUFFIX="-${@[${@[(Ie)--language]} + 1]}"
fi

OUT="$ROOT/.build/snapshots"
mkdir -p "$OUT"
swift build --product powerlens-snapshot
BIN="$(swift build --show-bin-path)/powerlens-snapshot"
"$BIN" --out "$OUT/panel$SUFFIX-light.png" "$@"
"$BIN" --out "$OUT/panel$SUFFIX-dark.png" --dark "$@"
