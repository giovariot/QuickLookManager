#!/bin/bash
# Compila dai sorgenti le librerie del modulo Video: dav1d, zimg e ffmpeg (arm64, librerie dinamiche).
# Stesse versioni di QLVideo di Marginal (GPL 2 o successiva), più le sue due patch a ffmpeg.
# Risultato in Vendor/ffmpeg (bin, include, lib); scripts/embed-video-libs.sh le mette nell'app.
# Nessuna dipendenza da Homebrew a runtime: gli strumenti di build (meson, ninja, pkg-config, autotools)
# servono solo qui e non finiscono nel pacchetto.
# Scarica ffmpeg (~200 MB di git), dav1d e zimg.
set -euo pipefail

FFMPEG_SHA=946fcce07b6dcd0331c8cc609192aeff5e1924f8
DAV1D_SHA=54706fc6bc0cdecab7e9593974a4039cc038fca7
ZIMG_SHA=f819b14e8f39d1282400b0d9543e8ef73c1b2bbd
MIN_MACOS=14.0

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/Vendor/build/video"
OUT="$ROOT/Vendor/ffmpeg"
mkdir -p "$WORK" "$OUT"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:$(dirname "$(xcrun -f clang)")"
export PKG_CONFIG_LIBDIR="$OUT/lib/pkgconfig"
export MACOSX_DEPLOYMENT_TARGET="$MIN_MACOS"
JOBS="$(sysctl -n hw.physicalcpu)"

fetch() { # nome url sha
  local dir="$WORK/$1"
  if [ ! -d "$dir/.git" ]; then mkdir -p "$dir"; git -C "$dir" init -q; git -C "$dir" remote add origin "$2"; fi
  git -C "$dir" remote set-url origin "$2"
  if [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)" != "$3" ]; then
    git -C "$dir" fetch --depth 1 origin "$3"
    git -C "$dir" checkout -q -f FETCH_HEAD
  fi
}

echo "== sorgenti"
fetch ffmpeg https://github.com/FFmpeg/FFmpeg.git "$FFMPEG_SHA"
fetch dav1d https://github.com/videolan/dav1d.git "$DAV1D_SHA"
fetch zimg https://github.com/sekrit-twc/zimg.git "$ZIMG_SHA"
git -C "$WORK/zimg" submodule update --init --depth 1 2>/dev/null || true

echo "== dav1d"
if [ ! -f "$OUT/lib/libdav1d.dylib" ]; then
  cat > "$WORK/cross-arm64.meson" <<EOF
[binaries]
c = ['/usr/bin/cc', '-arch', 'arm64', '-mmacosx-version-min=$MIN_MACOS', '-fapplication-extension']
pkg-config = 'pkg-config'
strip = '/usr/bin/strip'

[host_machine]
system = 'darwin'
subsystem = 'macos'
kernel = 'xnu'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF
  rm -rf "$WORK/build-dav1d"
  meson setup "$WORK/build-dav1d" "$WORK/dav1d" --cross-file "$WORK/cross-arm64.meson" --buildtype=release \
    -Ddefault_library=shared -Denable_tools=false -Denable_tests=false -Dprefix="$OUT"
  ninja -C "$WORK/build-dav1d" -j "$JOBS" install
  install_name_tool -id "@rpath/$(basename "$(otool -DX "$OUT/lib/libdav1d.dylib")")" "$OUT/lib/libdav1d.dylib"
fi

echo "== zimg"
if [ ! -f "$OUT/lib/libzimg.dylib" ]; then
  (cd "$WORK/zimg" && ./autogen.sh)
  rm -rf "$WORK/build-zimg"; mkdir -p "$WORK/build-zimg"
  (cd "$WORK/build-zimg" \
    && CPPFLAGS="-DNDEBUG -O3 -arch arm64 -mmacosx-version-min=$MIN_MACOS -fapplication-extension" LDFLAGS="-arch arm64" \
       "$WORK/zimg/configure" --host=aarch64-apple-darwin --prefix="$OUT" \
    && make -j"$JOBS" install)
  install_name_tool -id "@rpath/$(basename "$(otool -DX "$OUT/lib/libzimg.dylib")")" "$OUT/lib/libzimg.dylib"
fi

echo "== ffmpeg"
if [ ! -f "$OUT/lib/libavcodec.dylib" ]; then
  for p in "$ROOT"/scripts/video-patches/*.patch; do
    patch -d "$WORK/ffmpeg" -N -V none < "$p" > /dev/null && echo "patch $(basename "$p")" || echo "patch $(basename "$p") già applicata"
  done
  rm -rf "$WORK/build-ffmpeg"; mkdir -p "$WORK/build-ffmpeg"
  (cd "$WORK/build-ffmpeg" \
    && "$WORK/ffmpeg/configure" --prefix="$OUT" --arch=arm64 \
       --cc="clang -arch arm64 -mmacosx-version-min=$MIN_MACOS -fapplication-extension" \
       --enable-cross-compile --enable-vfp --enable-neon --disable-stripping \
       --enable-shared --enable-rpath --install-name-dir=@rpath --extra-ldflags=-liconv \
       --enable-gpl --disable-doc --disable-indevs --disable-outdevs --disable-network --disable-avdevice \
       --disable-muxers --disable-encoders --disable-bsfs --disable-filters --disable-protocols --disable-autodetect \
       --enable-appkit --enable-avfoundation --enable-bzlib --enable-coreimage --enable-iconv \
       --enable-libdav1d --enable-libzimg --enable-zlib --enable-audiotoolbox --enable-videotoolbox \
       --enable-bsf=extract_extradata --enable-bsf=mpeg4_unpack_bframes \
       --enable-filter=scale --enable-filter=tonemap --enable-filter=zscale \
       --enable-muxer=image2 --enable-muxer=mp4 --enable-muxer=m4v --enable-muxer=ipod --enable-muxer=matroska --enable-muxer=webm \
       --enable-encoder=png --enable-protocol=file --enable-protocol=pipe \
    && make -j"$JOBS" install)
  # Le librerie non devono portarsi dietro il percorso assoluto di build.
  for lib in libavcodec libavfilter libavformat libavutil libswresample libswscale; do
    f="$(realpath "$OUT/lib/$lib.dylib")"
    install_name_tool -delete_rpath "$OUT/lib" "$f" 2>/dev/null || true
  done
fi
cp -p "$WORK/build-ffmpeg/config.h" "$OUT/include/config.h"   # le estensioni usano anche intestazioni interne di ffmpeg
echo "OK: $(ls "$OUT/lib" | grep -E 'dylib$' | tr '\n' ' ')"
