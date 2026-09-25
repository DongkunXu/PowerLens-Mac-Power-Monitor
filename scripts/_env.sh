# Sourced by every script in this folder.
# Keeps all build byproducts inside the project: SwiftPM and the compiler write temporary
# directories, lock files and macro-expansion sources to $TMPDIR, and SwiftPM leaves some
# of them behind. Pointing TMPDIR into .build/ contains them, and the EXIT trap removes them.

ROOT="${0:A:h:h}"
cd "$ROOT"

export TMPDIR="$ROOT/.build/tmp"
mkdir -p "$TMPDIR"

_powerlens_cleanup_tmp() {
    if [[ -n "${TMPDIR:-}" && "$TMPDIR" == "$ROOT/.build/tmp" ]]; then
        rm -rf "$TMPDIR"
    fi
}
trap _powerlens_cleanup_tmp EXIT
