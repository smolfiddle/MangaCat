#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

KEYSTORE_DIR="android/keystore"
KEYSTORE_FILE="$KEYSTORE_DIR/mangacat-release.p12"
KEY_PROPERTIES="android/key.properties"

if [ -f "$KEY_PROPERTIES" ]; then
  echo "android/key.properties already exists; keeping the existing keystore."
  exit 0
fi
if [ -f "$KEYSTORE_FILE" ]; then
  echo "ERROR: $KEYSTORE_FILE exists but $KEY_PROPERTIES does not." >&2
  echo "Restore or recreate key.properties manually; refusing to overwrite the keystore." >&2
  exit 1
fi

mkdir -p "$KEYSTORE_DIR"
STORE_PASS="$(openssl rand -hex 24)"

keytool -genkeypair \
  -keystore "$KEYSTORE_FILE" \
  -storetype PKCS12 \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias mangacat \
  -storepass "$STORE_PASS" \
  -keypass "$STORE_PASS" \
  -dname "CN=MangaCat, OU=Mobile, O=smolfiddle, L=Manila, C=PH"

umask 077
cat > "$KEY_PROPERTIES" <<EOF
storePassword=$STORE_PASS
keyPassword=$STORE_PASS
keyAlias=mangacat
storeFile=keystore/mangacat-release.p12
EOF

echo
echo "Created $KEYSTORE_FILE and $KEY_PROPERTIES."
echo "Back both files up somewhere safe and private. Without them you cannot"
echo "ship updates that Android will install over this app."
