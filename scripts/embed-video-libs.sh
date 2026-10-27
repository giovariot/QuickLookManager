#!/bin/bash
# Fase di build dell'app: mette le librerie del modulo Video (ffmpeg, dav1d, zimg, compilate da scripts/vendor-video.sh)
# in Contents/Frameworks, dove QLMNative (e quindi le estensioni di anteprima e miniature) le trova con @rpath. Le firma con l'identità dell'app
# (library validation: devono avere lo stesso team).
set -euo pipefail
SRC="$SRCROOT/Vendor/ffmpeg/lib"
DEST="$BUILT_PRODUCTS_DIR/$FULL_PRODUCT_NAME/Contents/Frameworks"
if [ ! -d "$SRC" ]; then
  echo "warning: librerie video non compilate (scripts/vendor-video.sh): le estensioni video non funzioneranno."
  exit 0
fi
mkdir -p "$DEST"
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning | awk '/Apple Development|Developer ID Application/ {print $2; exit}')"
fi
COUNT=0
for lib in "$SRC"/*.dylib; do
  [ -L "$lib" ] && continue                      # i collegamenti simbolici non servono: si cerca il nome d'installazione
  NAME="$(basename "$(otool -DX "$lib")")"        # per esempio libavcodec.63.dylib
  cp -f "$lib" "$DEST/$NAME"
  [ -n "$IDENTITY" ] && codesign --force --sign "$IDENTITY" --options runtime "$DEST/$NAME"
  COUNT=$((COUNT + 1))
done
echo "Librerie video incorporate: $COUNT ($(du -sh "$DEST" | cut -f1) in Frameworks)"
