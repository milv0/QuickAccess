#!/bin/bash
set -e

VERSION="$1"
if [ -z "$VERSION" ]; then
  echo "Usage: ./release.sh <version>"
  echo "Example: ./release.sh 1.0.1"
  exit 1
fi

echo "🔨 Building..."
swiftc QuickAccess.swift -o QuickAccess.app/Contents/MacOS/QuickAccess -framework Cocoa

echo "📦 Creating DMG..."
hdiutil create -volname QuickAccess -srcfolder QuickAccess.app -ov -format UDZO QuickAccess.dmg

echo "📝 Updating version in code..."
sed -i '' "s/static let appVersion = \".*\"/static let appVersion = \"$VERSION\"/" QuickAccess.swift

echo "🔨 Rebuilding with new version..."
swiftc QuickAccess.swift -o QuickAccess.app/Contents/MacOS/QuickAccess -framework Cocoa
hdiutil create -volname QuickAccess -srcfolder QuickAccess.app -ov -format UDZO QuickAccess.dmg

echo "🚀 Committing and pushing..."
git add QuickAccess.swift
git commit -m "release: v$VERSION"
git tag "v$VERSION"
git push origin main
git push origin "v$VERSION"

echo "📤 Creating GitHub Release..."
gh release create "v$VERSION" QuickAccess.dmg --title "v$VERSION" --generate-notes

echo "✅ Done! Released v$VERSION"
