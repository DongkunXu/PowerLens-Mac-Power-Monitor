#!/bin/zsh
# Re-checks that the data sources PowerLens relies on still measure correctly (run after macOS
# updates). Takes about 2 minutes and briefly loads CPU, GPU and Neural Engine.
# Requirements: lid open, machine awake; results are noisier while other work is running.
set -euo pipefail
source "${0:A:h}/_env.sh"

if ioreg -r -k AppleClamshellState -d 4 | grep -q '"AppleClamshellState" = Yes'; then
    echo "Lid is closed: the machine sleeps between samples and the numbers are meaningless." >&2
    exit 1
fi

OUT="$ROOT/.build/validation"
mkdir -p "$OUT"
SRC="$ROOT/tools/validation"
PROBES="$ROOT/Sources/CProbes"

clang -O2 -I "$PROBES/include" -framework IOKit \
    "$SRC/cpu_energy_vs_system.c" "$PROBES/probes.c" -o "$OUT/cpu_energy_vs_system"
clang -O2 -I "$PROBES/include" -framework IOKit -framework CoreFoundation -lIOReport \
    "$SRC/coalition_vs_chip.c" "$PROBES/probes.c" -o "$OUT/coalition_vs_chip"
clang -O2 -I "$PROBES/include" -framework IOKit \
    "$SRC/process_energy.c" "$PROBES/probes.c" -o "$OUT/process_energy"
swiftc -O "$SRC/synthetic_load.swift" -o "$OUT/synthetic_load" -module-cache-path "$TMPDIR/module-cache"

LOAD_PID=""
stop_load() {
    if [[ -n "$LOAD_PID" ]]; then
        kill "$LOAD_PID" 2>/dev/null || true
        wait "$LOAD_PID" 2>/dev/null || true
    fi
    LOAD_PID=""
}
# The Neural Engine compiler caches models per executable name in ~/Library/Caches/<name>.
cleanup_validation() {
    stop_load
    rm -rf "$HOME/Library/Caches/synthetic_load" "$(getconf DARWIN_USER_CACHE_DIR)synthetic_load"
    _powerlens_cleanup_tmp
}
trap cleanup_validation EXIT

echo "== 1. CPU: kernel per-process energy vs rise in SMC system power"
echo "   expect: workers' energy explains most of the rise (shared cluster/fabric cost is not billed)"
for n in 1 3 6; do "$OUT/cpu_energy_vs_system" "$n" 8; sleep 3; done

echo "== 2. Idle baseline"
"$OUT/coalition_vs_chip" 5

echo "== 3. GPU load: per-app GPU energy summed vs chip GPU counter (expect close agreement)"
"$OUT/synthetic_load" gpu 8 & LOAD_PID=$!
sleep 1; "$OUT/coalition_vs_chip" 5; stop_load; sleep 2

echo "== 4. Neural Engine load: per-app ANE energy (the chip ANE counter reads 0 on macOS 27)"
# The first run compiles the model for the Neural Engine (CPU-heavy, in aned's coalition);
# only later runs execute on the ANE. Warm up before measuring.
"$OUT/synthetic_load" ane 10 >/dev/null
"$OUT/synthetic_load" ane 9 & LOAD_PID=$!
sleep 2; "$OUT/coalition_vs_chip" 5; stop_load

echo "== 5. PowerLens's own overhead (panel closed = 3 s sampling)"
if PL_PID=$(pgrep -x PowerLens); then
    "$OUT/process_energy" "$PL_PID" 30
else
    echo "   PowerLens is not running; skipped"
fi

echo "Done. Binaries are in $OUT (removed by scripts/clean.sh)."
