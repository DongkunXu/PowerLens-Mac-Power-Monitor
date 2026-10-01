#!/bin/zsh
# Builds PowerLens.app (release), optionally installing it.
#   scripts/build-app.sh            -> build/stage.noindex/PowerLens.app
#   scripts/build-app.sh --install  -> installs to /Applications (or ~/Applications), launches it
#                                      and removes the staged copy
set -euo pipefail
source "${0:A:h}/_env.sh"

BUNDLE_ID="io.github.dongkunxu.PowerLens"

swift build -c release --product PowerLens
BIN="$(swift build -c release --show-bin-path)/PowerLens"

APP="$STAGED_APP"
_powerlens_remove_staged_app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PowerLens"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature: required for SMAppService (launch at login).
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    DEST_DIR="/Applications"
    [[ -w "$DEST_DIR" ]] || DEST_DIR="$HOME/Applications"
    mkdir -p "$DEST_DIR"
    DEST="$DEST_DIR/PowerLens.app"

    if pgrep -x PowerLens >/dev/null; then
        osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
        for _ in {1..20}; do pgrep -x PowerLens >/dev/null || break; sleep 0.25; done
        if pgrep -x PowerLens >/dev/null; then
            echo "PowerLens is still running; quit it and re-run." >&2
            exit 1
        fi
    fi

    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    _powerlens_remove_staged_app
    # Refresh the Dock / Finder icon cache entry for the replaced bundle.
    touch "$DEST"
    "$LSREGISTER" -f "$DEST"
    open "$DEST"
    echo "Installed and launched $DEST"
fi
