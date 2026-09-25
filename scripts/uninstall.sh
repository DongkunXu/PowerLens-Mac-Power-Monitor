#!/bin/zsh
# Removes the installed app and everything it created outside this project:
# login item, preferences, caches (incl. Metal shader cache) and saved state.
set -euo pipefail

BUNDLE_ID="io.github.dongkunxu.PowerLens"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

for APP in /Applications/PowerLens.app "$HOME/Applications/PowerLens.app"; do
    [[ -d "$APP" ]] || continue
    # Let the app remove its own login item (SMAppService) before the bundle disappears.
    "$APP/Contents/MacOS/PowerLens" --unregister-login-item || echo "warning: could not unregister login item" >&2
done

if pgrep -x PowerLens >/dev/null; then
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    for _ in {1..20}; do pgrep -x PowerLens >/dev/null || break; sleep 0.25; done
    pkill -x PowerLens 2>/dev/null || true
fi

for APP in /Applications/PowerLens.app "$HOME/Applications/PowerLens.app"; do
    [[ -d "$APP" ]] || continue
    "$LSREGISTER" -u "$APP" 2>/dev/null || true
    rm -rf "$APP"
    echo "Removed $APP"
done

defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
rm -f "$HOME/Library/Preferences/$BUNDLE_ID.plist"
rm -rf "$HOME/Library/Caches/$BUNDLE_ID" \
       "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState" \
       "$HOME/Library/HTTPStorages/$BUNDLE_ID" \
       "$(getconf DARWIN_USER_CACHE_DIR)$BUNDLE_ID" \
       "$(getconf DARWIN_USER_TEMP_DIR)$BUNDLE_ID"
echo "Removed preferences, caches and saved state for $BUNDLE_ID"
