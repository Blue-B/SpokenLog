#!/bin/bash
# Keep app data by default. The app itself asks which categories to delete.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/SpokenLog.app"
if [[ ! -d "$APP" ]]; then APP='/Applications/SpokenLog.app'; fi
if [[ ! -d "$APP" ]]; then
  printf 'SpokenLog.app not found. Place this helper next to the app.\n'
  read -r -p 'Press Return to close.' _
  exit 1
fi
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")
[[ "$BUNDLE_ID" == 'io.github.blueb.spokenlog' ]] || { printf 'Unexpected application. Nothing removed.\n'; exit 1; }
BINARY=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")
[[ "$BINARY" == 'SpokenLog' ]] || { printf 'Unexpected executable. Nothing removed.\n'; exit 1; }
if pgrep -x 'SpokenLog' >/dev/null; then
  printf 'Close all SpokenLog windows, then run this helper again.\n'
  read -r -p 'Press Return to close.' _
  exit 1
fi
# Cancel/error stops here without moving the application.
SPOKENLOG_UNINSTALL=1 "$APP/Contents/MacOS/$BINARY"
# Finder moves only the identified .app to Trash; no recursive shell deletion.
osascript - "$APP" <<'APPLESCRIPT'
on run argv
  set appFile to POSIX file (item 1 of argv) as alias
  display dialog "Move SpokenLog.app to Trash? Data is kept unless you explicitly deleted it in the app." buttons {"Cancel", "Move to Trash"} default button "Cancel" cancel button "Cancel" with title "Uninstall SpokenLog"
  tell application "Finder" to delete appFile
end run
APPLESCRIPT
printf 'SpokenLog moved to Trash. Data was kept unless explicitly selected in the app.\n'
