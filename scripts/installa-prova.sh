#!/bin/bash
# Mette la build Release di prova in /Applications e la registra, togliendo la registrazione della copia in build/.
# Uso: scripts/installa-prova.sh   (dopo xcodebuild -configuration Release -derivedDataPath build/DerivedData)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
A="$ROOT/build/DerivedData/Build/Products/Release/QuickLookManager.app"
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
for e in QLMPreview QLMThumbnail; do pluginkit -r "$A/Contents/PlugIns/$e.appex" 2>/dev/null || true; done
"$LSR" -u "$A" 2>/dev/null || true
osascript -e 'tell application "QuickLookManager" to quit' 2>/dev/null || true
rm -rf /Applications/QuickLookManager.app
ditto "$A" /Applications/QuickLookManager.app
xattr -dr com.apple.quarantine /Applications/QuickLookManager.app 2>/dev/null || true
open -a /Applications/QuickLookManager.app
sleep 3
pluginkit -e use -i com.giovariot.QuickLookManager.Preview
pluginkit -e use -i com.giovariot.QuickLookManager.Thumbnail
qlmanage -r >/dev/null 2>&1; qlmanage -r cache >/dev/null 2>&1
pluginkit -mAD 2>&1 | grep -i quicklookmanager
