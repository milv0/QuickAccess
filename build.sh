#!/bin/bash
set -e
cd "$(dirname "$0")"

# Get version from code
VERSION=$(grep "appVersion" QuickAccess.swift | head -1 | sed 's/.*"\(.*\)".*/\1/')
echo "🔨 Building QuickAccess v$VERSION..."

# Build
mkdir -p QuickAccess.app/Contents/MacOS
git checkout HEAD -- QuickAccess.app/Contents/Info.plist QuickAccess.app/Contents/Resources/AppIcon.icns 2>/dev/null || true
swiftc QuickAccess.swift -o QuickAccess.app/Contents/MacOS/QuickAccess -framework Cocoa -framework SwiftUI

# Create zip
ZIP_NAME="QuickAccess-v$VERSION.zip"
rm -f docs/$ZIP_NAME
zip -r docs/$ZIP_NAME QuickAccess.app install.sh
echo "✅ Build complete: docs/$ZIP_NAME"

# Deploy to public repo
DEPLOY_DIR="/tmp/quickaccess-app-deploy"
rm -rf $DEPLOY_DIR
git clone https://github.com/milv0/quickaccess-app.git $DEPLOY_DIR 2>/dev/null
rm -f $DEPLOY_DIR/QuickAccess-v*.zip
cp docs/$ZIP_NAME $DEPLOY_DIR/
cp docs/index.html $DEPLOY_DIR/
cp docs/install.sh $DEPLOY_DIR/
cp docs/uninstall.sh $DEPLOY_DIR/

# Update version in deployed files
sed -i '' "s/QuickAccess-v[0-9.]*.zip/QuickAccess-v$VERSION.zip/g" $DEPLOY_DIR/install.sh $DEPLOY_DIR/index.html

cd $DEPLOY_DIR
git add -A
git commit -m "release: v$VERSION" 2>/dev/null && git push origin main 2>/dev/null && echo "🚀 Deployed to milv0.github.io/quickaccess-app/" || echo "ℹ️ No changes to deploy"
rm -rf $DEPLOY_DIR

echo "✅ Done! v$VERSION"
