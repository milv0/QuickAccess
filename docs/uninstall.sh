#!/bin/bash
set -e
echo "🗑️ Uninstalling QuickAccess..."
killall QuickAccess 2>/dev/null || true
rm -rf /Applications/QuickAccess.app
rm -f ~/.quickaccess.json
echo "✅ QuickAccess removed."
