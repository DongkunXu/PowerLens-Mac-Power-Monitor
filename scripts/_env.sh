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

# The app bundle is staged in a ".noindex" folder: Spotlight skips it, so a build copy never
# shows up next to the installed app. Installing and packaging remove it when they are done.
STAGED_APP="$ROOT/build/stage.noindex/PowerLens.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

_powerlens_remove_staged_app() {
    if [[ -d "$STAGED_APP" ]]; then
        "$LSREGISTER" -u "$STAGED_APP" 2>/dev/null || true
    fi
    rm -rf "${STAGED_APP:h}"
    rmdir "$ROOT/build" 2>/dev/null || true
}
