#!/bin/bash
# Compila Ghostscript (AGPL v3) dai sorgenti in Vendor/build/ghostscript, per il modulo EPS.
# Il risultato (Vendor/ghostscript) viene incorporato nell'app da scripts/embed-ghostscript.sh.
# Nessuna dipendenza da Homebrew: PATH ripulito, librerie incluse nei sorgenti di Ghostscript.
# Uso: scripts/vendor-ghostscript.sh [versione]   (predefinita 10.08.0)
# Scarica ~90 MB da github.com/ArtifexSoftware/ghostpdl-downloads e compila per qualche minuto.
set -euo pipefail
V="${1:-10.08.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/Vendor/build/ghostscript"
OUT="$ROOT/Vendor/ghostscript"
mkdir -p "$WORK" "$OUT"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$(dirname "$(xcrun -f clang)")"
unset PKG_CONFIG PKG_CONFIG_PATH CPATH LIBRARY_PATH
cd "$WORK"
TAR="ghostscript-$V.tar.gz"
if [ ! -f "$TAR" ]; then
  curl -fL -o "$TAR" "https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/gs${V//./}/$TAR"
fi
[ -d "ghostscript-$V" ] || tar xzf "$TAR"
cd "ghostscript-$V"
export CFLAGS="-O2 -mmacosx-version-min=14.0 -arch arm64" LDFLAGS="-arch arm64"
./configure --prefix="$OUT" --disable-cups --disable-gtk --without-x --without-libpaper \
  --disable-fontconfig --without-tesseract --without-pdftoraster --host=aarch64-apple-darwin
make -j"$(sysctl -n hw.ncpu)" so
make soinstall
echo "OK: $(ls "$OUT/lib")"
