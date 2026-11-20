#!/usr/bin/env bash
# בונה FFmpeg קטן לעיבוד שמע (חיתוך, fade, הפחתת רעש, ייצוא AAC/M4A).
# עובד על Linux / macOS, וב-Windows דרך MSYS2 / Git Bash.
# הפלט: third_party/ffmpeg/bin/ffmpeg (או ffmpeg.exe ב-Windows).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/ffmpeg-9.0.2"
BUILD="$HERE/build"
OUT="$HERE/bin"

EXE=""
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) EXE=".exe" ;;
esac

JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

rm -rf "$BUILD"
mkdir -p "$BUILD" "$OUT"
cd "$BUILD"

"$SRC/configure" \
  --disable-everything --disable-programs --enable-ffmpeg \
  --disable-doc --disable-asm --disable-network --disable-autodetect \
  --disable-debug --enable-small \
  --enable-protocol=file,pipe \
  --enable-demuxer=mp3,wav,flac,ogg,aac,mov,matroska \
  --enable-muxer=mp4,ipod,wav,mp3,adts,ogg \
  --enable-decoder=mp3,mp3float,pcm_s16le,pcm_s24le,pcm_f32le,flac,vorbis,aac,aac_fixed,opus \
  --enable-encoder=aac,pcm_s16le \
  --enable-parser=mpegaudio,aac,flac,vorbis,opus \
  --enable-filter=atrim,afade,afftdn,anlmdn,aresample,asetpts,volume,aformat,anull \
  --enable-bsf=aac_adtstoasc

make -j"$JOBS"
cp "ffmpeg$EXE" "$OUT/ffmpeg$EXE"
"$OUT/ffmpeg$EXE" -version | head -1
echo "OK: $OUT/ffmpeg$EXE"
