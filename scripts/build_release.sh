#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION_LINE="$(grep -E '^version:' pubspec.yaml | head -1 | awk '{print $2}')"
VERSION="${VERSION_LINE%%+*}"
BUILD="${VERSION_LINE##*+}"
DIST="dist/mangacat-$VERSION"

if [ ! -f android/key.properties ]; then
  echo "Signing: no android/key.properties found, release builds use debug keys."
  echo "Run scripts/generate_keystore.sh to create a real release keystore."
fi

flutter pub get

EXTRA_ARGS=()
if [ "${OBFUSCATE:-0}" = "1" ]; then
  EXTRA_ARGS+=(--obfuscate --split-debug-info=build/symbols)
fi

flutter build appbundle --release "${EXTRA_ARGS[@]}"

flutter build apk --release --split-per-abi "${EXTRA_ARGS[@]}"

if [ "${UNIVERSAL:-0}" = "1" ]; then
  flutter build apk --release "${EXTRA_ARGS[@]}"
fi

rm -rf "$DIST"
mkdir -p "$DIST"

if [ "${OBFUSCATE:-0}" = "1" ]; then
  cp -r build/symbols "$DIST/symbols"
fi

cp build/app/outputs/bundle/release/app-release.aab "$DIST/mangacat-$VERSION.aab"
for apk in build/app/outputs/flutter-apk/app-*-release.apk; do
  abi="$(basename "$apk" | sed -E 's/^app-(.*)-release\.apk$/\1/')"
  cp "$apk" "$DIST/mangacat-$VERSION-$abi.apk"
done
if [ "${UNIVERSAL:-0}" = "1" ]; then
  cp build/app/outputs/flutter-apk/app-release.apk "$DIST/mangacat-$VERSION-universal.apk"
fi

(
  cd "$DIST"
  sha256sum ./* > SHA256SUMS
)

echo
echo "Artifacts for MangaCat $VERSION (build $BUILD):"
ls -lh "$DIST"
