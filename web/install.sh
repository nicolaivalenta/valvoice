#!/bin/bash
# ValVoice installer — pulls the latest release from GitHub, drops it in /Applications,
# strips Gatekeeper quarantine, and launches the app.
#
# Usage (copy-paste into Terminal):
#   curl -fsSL https://valvoice.app/install | bash

set -euo pipefail

REPO="nicolaivalenta/valvoice"
APP_NAME="ValVoice.app"
APP_PATH="/Applications/$APP_NAME"
ZIP_URL="https://github.com/$REPO/releases/latest/download/ValVoice.zip"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

say() { printf "\033[1;33m→\033[0m %s\n" "$*"; }
ok()  { printf "\033[1;32m✓\033[0m %s\n" "$*"; }

say "Downloading ValVoice…"
curl -fsSL -o "$TMP/ValVoice.zip" "$ZIP_URL"

say "Unpacking…"
unzip -q -o "$TMP/ValVoice.zip" -d "$TMP"

# If ValVoice is currently running, quit it
osascript -e "tell application \"ValVoice\" to quit" 2>/dev/null || true
sleep 1

say "Installing to /Applications…"
rm -rf "$APP_PATH"
mv "$TMP/$APP_NAME" "$APP_PATH"

# Strip quarantine so Gatekeeper doesn't block launch
xattr -cr "$APP_PATH"

say "Launching…"
open "$APP_PATH"

ok "ValVoice installed. Press Caps Lock to dictate."
echo ""
echo "   Next steps:"
echo "   1. System Settings → Privacy & Security → Accessibility — enable ValVoice"
echo "   2. System Settings → Privacy & Security → Microphone — enable ValVoice"
