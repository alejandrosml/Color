#!/bin/bash
# SPDX-License-Identifier: MIT
# Builds the Rust core of Color for Android: one libedupaint_core.so per
# processor that Flutter supports, linked by the NDK for Android 8 (API 26),
# aligned on pages of 16 KB as Google Play asks, and placed where Gradle
# packs them: prototypes/flutter-rust/android/app/src/main/jniLibs/<abi>/.
#
#   construire-le-coeur.sh [cargo]
#
# ANDROID_NDK_HOME names the NDK (by default the one Flutter asks for, in
# ANDROID_HOME). The cargo given, or found, must know the three targets
# aarch64-linux-android, armv7-linux-androideabi and x86_64-linux-android.
# The dependencies come from vendor/ only: nothing is downloaded.
set -euo pipefail
ICI="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$ICI/../.." && pwd)"
COEUR="$RACINE/prototypes/native-swift-rust/core"
SORTIE="$RACINE/prototypes/flutter-rust/android/app/src/main/jniLibs"
CARGO="${1:-cargo}"
NDK="${ANDROID_NDK_HOME:-${ANDROID_HOME:-}/ndk/28.2.13676358}"
API=26
case "$(uname -s)" in
  Darwin) HOTE=darwin-x86_64 ;;
  Linux) HOTE=linux-x86_64 ;;
  *) echo "Système inconnu : $(uname -s)" >&2; exit 1 ;;
esac
OUTILS="$NDK/toolchains/llvm/prebuilt/$HOTE/bin"
if [ ! -x "$OUTILS/clang" ]; then
  echo "Le NDK d'Android est introuvable : $NDK" >&2
  exit 1
fi
cd "$COEUR"
for paire in aarch64-linux-android:arm64-v8a:aarch64-linux-android \
             armv7-linux-androideabi:armeabi-v7a:armv7a-linux-androideabi \
             x86_64-linux-android:x86_64:x86_64-linux-android; do
  CIBLE="${paire%%:*}"
  reste="${paire#*:}"
  ABI="${reste%%:*}"
  CLANG="${reste#*:}${API}-clang"
  VARIABLE="CARGO_TARGET_$(echo "$CIBLE" | tr 'a-z-' 'A-Z_')_LINKER"
  export "$VARIABLE=$OUTILS/$CLANG"
  echo "Cœur pour Android, $ABI…"
  "$CARGO" rustc --release --lib --offline --frozen --target "$CIBLE" --crate-type cdylib -- \
    -C link-arg=-Wl,-soname,libedupaint_core.so \
    -C link-arg=-Wl,-z,max-page-size=16384
  mkdir -p "$SORTIE/$ABI"
  CIBLES="${CARGO_TARGET_DIR:-$COEUR/target}"
  cp "$CIBLES/$CIBLE/release/libedupaint_core.so" "$SORTIE/$ABI/libedupaint_core.so"
done
echo "Bibliothèques du cœur pour Android : $SORTIE"
