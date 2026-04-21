#!/bin/bash
# Rebuild + sign + install ValVoice. Uses stable self-signed cert so Accessibility grant persists.
set -euo pipefail

cd ~/VoiceInk

# Ensure signing identity exists
./scripts/setup-signing.sh

echo "→ Quitting running instance..."
osascript -e 'tell application "ValVoice" to quit' 2>/dev/null || true
pkill -9 -f "ValVoice.app" 2>/dev/null || true
sleep 1

echo "→ Building..."
xcodebuild \
    -project VoiceInk.xcodeproj \
    -scheme VoiceInk \
    -configuration Release \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
    -derivedDataPath /tmp/valvoice-build \
    build 2>&1 | tail -3

echo "→ Installing..."
rm -rf /Applications/ValVoice.app
mv /tmp/valvoice-build/Build/Products/Release/VoiceInk.app /Applications/ValVoice.app

# Patch CFBundleName to ValVoice (Xcode derives it from PRODUCT_NAME otherwise)
/usr/libexec/PlistBuddy -c "Add :CFBundleName string ValVoice" /Applications/ValVoice.app/Contents/Info.plist 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :CFBundleName ValVoice" /Applications/ValVoice.app/Contents/Info.plist

echo "→ Signing with ValVoice Developer..."
codesign --force --deep --sign "ValVoice Developer" /Applications/ValVoice.app 2>&1 | tail -1

echo "→ Launching..."
open /Applications/ValVoice.app

echo ""
echo "✓ Installed. If Accessibility is already granted for ValVoice.app, it still is."
