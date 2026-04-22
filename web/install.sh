#!/bin/bash
# ValVoice installer — pulls the latest release from GitHub, drops it in /Applications,
# strips Gatekeeper quarantine, and launches the app.
#
# Usage (copy-paste into Terminal):
#   curl -fsSL https://valvoice.app/install | bash

set -euo pipefail

err() { printf "\033[1;31m✗\033[0m %s\n" "$*" >&2; }

# Apple Silicon required — the app is an arm64-only binary (whisper.xcframework
# and Parakeet both depend on it). Intel Macs can't execute it.
if [ "$(uname -m)" != "arm64" ]; then
  err "ValVoice requires an Apple Silicon Mac (M1/M2/M3/M4)."
  err "Detected architecture: $(uname -m). Intel Macs aren't supported."
  err "More info: https://valvoice.pages.dev/troubleshooting"
  exit 1
fi

# macOS 13+ required for the app's runtime APIs.
os_major=$(sw_vers -productVersion | cut -d. -f1)
if [ "${os_major:-0}" -lt 13 ]; then
  err "ValVoice requires macOS 13 (Ventura) or later."
  err "Detected: macOS $(sw_vers -productVersion)."
  exit 1
fi

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
