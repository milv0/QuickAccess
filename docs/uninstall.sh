#!/bin/bash
set -e
VERSION=$(defaults read com.mingyupark.QuickAccess appVersion 2>/dev/null || echo "unknown")
echo "🗑️ Uninstalling QuickAccess v$VERSION..."
killall QuickAccess 2>/dev/null || true
osascript -e 'tell application "System Events" to delete login item "QuickAccess"' 2>/dev/null || true
rm -rf /Applications/QuickAccess.app
rm -f ~/.quickaccess.json
defaults delete com.mingyupark.QuickAccess 2>/dev/null || true
echo "✅ QuickAccess v$VERSION removed (app + config + login item + preferences)."
