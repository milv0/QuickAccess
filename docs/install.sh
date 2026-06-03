#!/bin/bash
set -e
echo "⚡ Installing QuickAccess..."
cd /tmp
curl -sL https://milv0.github.io/QuickAccess/QuickAccess.zip -o QuickAccess.zip
unzip -qo QuickAccess.zip
xattr -cr QuickAccess.app
mv QuickAccess.app /Applications/
rm -f QuickAccess.zip
echo "✅ Installed to /Applications/QuickAccess.app"
echo "🚀 Launching..."
open /Applications/QuickAccess.app
