#!/bin/bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
echo "⚡ Installing QuickAccess..."
xattr -cr "$DIR/QuickAccess.app"
cp -R "$DIR/QuickAccess.app" /Applications/
echo "✅ Installed to /Applications/QuickAccess.app"
echo "🚀 Launching..."
open /Applications/QuickAccess.app
