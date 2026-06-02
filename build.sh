#!/bin/bash
set -e
cd "$(dirname "$0")"
mkdir -p QuickAccess.app/Contents/MacOS
swiftc QuickAccess.swift -o QuickAccess.app/Contents/MacOS/QuickAccess -framework Cocoa
echo "✅ Build complete. Run: open QuickAccess.app"
