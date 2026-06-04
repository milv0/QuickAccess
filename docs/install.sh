#!/bin/bash
set -e
VERSION="2.2.7"
echo "⚡ Installing QuickAccess v$VERSION..."
cd /tmp
curl -sL https://milv0.github.io/QuickAccess/QuickAccess-v$VERSION.zip -o QuickAccess.zip
unzip -qo QuickAccess.zip
xattr -cr QuickAccess.app
rm -rf /Applications/QuickAccess.app
mv QuickAccess.app /Applications/
rm -f QuickAccess.zip
echo "✅ QuickAccess v$VERSION installed to /Applications/"
echo "🚀 Launching..."
open /Applications/QuickAccess.app
