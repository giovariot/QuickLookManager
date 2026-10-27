#!/bin/bash
# Fase di build di QLMCore: mette Ghostscript (compilato da scripts/vendor-ghostscript.sh) dentro il framework,
# così l'app si installa copiandola. Se Vendor/ghostscript non c'è, il modulo EPS usa solo le anteprime incorporate.
set -euo pipefail
SRC="$SRCROOT/Vendor/ghostscript"
DEST="$BUILT_PRODUCTS_DIR/$FULL_PRODUCT_NAME/Versions/A/Resources/Ghostscript"
if [ ! -d "$SRC/lib" ]; then
  echo "warning: Ghostscript non compilato (scripts/vendor-ghostscript.sh): il modulo EPS non potrà disegnare file senza anteprima."
  rm -rf "$DEST"
  exit 0
fi
rm -rf "$DEST"; mkdir -p "$DEST"
LIB="$(ls "$SRC"/lib/libgs.*.*.dylib 2>/dev/null | head -1)"
[ -n "$LIB" ] || LIB="$(ls "$SRC"/lib/libgs.dylib | head -1)"
cp -L "$LIB" "$DEST/libgs.dylib"
install_name_tool -id "@rpath/libgs.dylib" "$DEST/libgs.dylib"
# `make soinstall` non installa Resource né iccprofiles: si prendono dall'albero dei sorgenti.
SRCTREE="$(ls -d "$SRCROOT"/Vendor/build/ghostscript/ghostscript-*/ | head -1)"
RES="$(ls -d "$SRC"/share/ghostscript/*/Resource 2>/dev/null | head -1 || true)"
[ -n "$RES" ] || RES="${SRCTREE}Resource"
BASE="$(dirname "$RES")"
cp -R "$RES" "$DEST/Resource"
[ -d "$BASE/iccprofiles" ] && cp -R "$BASE/iccprofiles" "$DEST/iccprofiles" || cp -R "${SRCTREE}iccprofiles" "$DEST/iccprofiles"
LIBDIR="$(ls -d "$SRC"/share/ghostscript/*/lib 2>/dev/null | head -1 || true)"
[ -n "$LIBDIR" ] && cp -R "$LIBDIR" "$DEST/lib"
# Una libreria caricata a runtime deve avere la firma dello stesso team dell'app (library validation).
# Nella fase di build di un framework Xcode non espone EXPANDED_CODE_SIGN_IDENTITY: si prende la prima identità
# di sviluppo valida del portachiavi (stesso team dell'app).
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning | awk '/Apple Development|Developer ID Application/ {print $2; exit}')"
fi
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" --options runtime "$DEST/libgs.dylib"
else
  echo "warning: nessuna identità di firma: libgs non sarà caricabile dall'estensione."
fi
echo "Ghostscript incorporato: $(du -sh "$DEST" | cut -f1)"
