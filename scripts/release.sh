#!/bin/bash
# Compila la build Release, controlla che dentro ci sia tutto e fa il DMG in dist/.
# Il controllo esiste perché un'app a cui manca un pezzo (Ghostscript, una
# libreria video, un'estensione) da fuori sembra a posto: qui la build fallisce.
# Uso: scripts/release.sh        (la versione è MARKETING_VERSION in project.yml)
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
V=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml | head -1)
[ -n "$V" ] || { echo "release.sh: versione non trovata in project.yml" >&2; exit 1; }
DD="$ROOT/build/DerivedData"
APP="$DD/Build/Products/Release/QuickLookManager.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

python3 scripts/gen-types.py
xcodegen generate
xcodebuild -project QuickLookManager.xcodeproj -scheme QuickLookManager -configuration Release \
    -derivedDataPath "$DD" build

# Xcode registra le estensioni dalla cartella di build: si tolgono subito,
# altrimenti prendono il posto di quelle dell'app installata.
for x in "$APP"/Contents/PlugIns/*.appex; do pluginkit -r "$x" 2>/dev/null || true; done
"$LSREGISTER" -u "$APP" 2>/dev/null || true

FAIL=0
no() { echo "  MANCA  $1" >&2; FAIL=1; }
C="$APP/Contents"
for p in MacOS/QuickLookManager MacOS/IconeAgent \
         PlugIns/QLMPreview.appex PlugIns/QLMThumbnail.appex \
         Frameworks/QLMCore.framework Frameworks/QLMNative.framework Frameworks/AssetCarReader.framework \
         Frameworks/QLMCore.framework/Versions/A/Resources/Ghostscript/libgs.dylib \
         Frameworks/QLMCore.framework/Versions/A/Resources/Ghostscript/Resource \
         Frameworks/QLMCore.framework/Versions/A/Resources/Ghostscript/iccprofiles; do
    [ -e "$C/$p" ] || no "$p"
done
for l in avcodec avfilter avformat avutil dav1d swresample swscale zimg; do
    ls "$C"/Frameworks/lib$l.*.dylib >/dev/null 2>&1 || no "Frameworks/lib$l"
done
for w in preview.js hljs.js yaml.js mermaid.js asciidoctor.js katex.min.css; do
    [ -n "$(find "$C" -name "$w" -path '*Web*' | head -1)" ] || no "Web/$w"
done
got=$(plutil -extract CFBundleShortVersionString raw "$C/Info.plist")
[ "$got" = "$V" ] || { echo "  versione nell'app: $got, attesa $V" >&2; FAIL=1; }
for x in "$C"/PlugIns/*.appex; do
    xv=$(plutil -extract CFBundleShortVersionString raw "$x/Contents/Info.plist")
    [ "$xv" = "$V" ] || { echo "  versione di $(basename "$x"): $xv, attesa $V" >&2; FAIL=1; }
done
lipo -archs "$C/MacOS/QuickLookManager" | grep -q arm64 || no "architettura arm64"
codesign --verify --deep --strict "$APP" || { echo "  firma non valida" >&2; FAIL=1; }
[ "$FAIL" = 0 ] || { echo "release.sh: l'app è incompleta, nessun DMG creato." >&2; exit 1; }

STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir -p dist
DMG="dist/QuickLookManager-$V.dmg"
rm -f "$DMG"
hdiutil create -volname "QuickLook Manager $V" -srcfolder "$STAGE" -format UDZO -quiet "$DMG"
rm -rf "$STAGE"
echo "OK: $DMG"
