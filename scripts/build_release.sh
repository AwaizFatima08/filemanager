#!/usr/bin/env bash
# Builds the signed release AAB and APK with the real AdMob ids.
#
#   bash scripts/build_release.sh
#
# Ids come from .secrets/ad-units.env (ADMOB_APP_ID, AD_BANNER_ID, AD_INTERSTITIAL_ID).
# A plain `flutter build` without them gives an ad-free release (and Google's test
# app id in the manifest), so always release with this script.
set -euo pipefail
cd "$(dirname "$0")/.."

ENV=.secrets/ad-units.env
[ -f "$ENV" ] || { echo "Missing $ENV"; exit 1; }
[ -f android/key.properties ] || { echo "Missing android/key.properties (upload key)"; exit 1; }
# shellcheck disable=SC1090
source "$ENV"
for v in ADMOB_APP_ID AD_BANNER_ID AD_INTERSTITIAL_ID; do
  [ -n "${!v:-}" ] || { echo "$v is empty in $ENV"; exit 1; }
  case "${!v}" in *3940256099942544*) echo "$v is still Google's test id"; exit 1;; esac
done
export ADMOB_APP_ID

DEFINES=(--dart-define=AD_BANNER_ID="$AD_BANNER_ID" --dart-define=AD_INTERSTITIAL_ID="$AD_INTERSTITIAL_ID")
VERSION="$(sed -n 's/^version: //p' pubspec.yaml)"   # e.g. 1.1.0+2
OUT="releases/v${VERSION/+/-}"

flutter build appbundle --release "${DEFINES[@]}"
flutter build apk --release "${DEFINES[@]}"
mkdir -p "$OUT"
cp build/app/outputs/bundle/release/app-release.aab "$OUT/filemanager-${VERSION/+/-}.aab"
cp build/app/outputs/flutter-apk/app-release.apk "$OUT/filemanager-${VERSION/+/-}.apk"

# The manifest must carry the real app id, never the test one.
AAPT="$(ls -d "$HOME"/Android/Sdk/build-tools/*/ | tail -1)aapt"
MANIFEST="$("$AAPT" dump xmltree "$OUT/filemanager-${VERSION/+/-}.apk" AndroidManifest.xml)"
grep -q "$ADMOB_APP_ID" <<<"$MANIFEST" || { echo "FAIL: release manifest does not carry ADMOB_APP_ID"; exit 1; }
if grep -q 3940256099942544 <<<"$MANIFEST"; then echo "FAIL: release manifest has the test AdMob app id"; exit 1; fi
# The real unit ids must be compiled into the Dart code.
LIBAPP="$(unzip -p "$OUT/filemanager-${VERSION/+/-}.apk" lib/arm64-v8a/libapp.so | strings)"
for id in "$AD_BANNER_ID" "$AD_INTERSTITIAL_ID"; do
  grep -qF "$id" <<<"$LIBAPP" || { echo "FAIL: $id not found in libapp.so"; exit 1; }
done
# Must be signed with the upload key (.secrets/filemanager-upload.jks), never the debug key.
APKSIGNER="$(ls -d "$HOME"/Android/Sdk/build-tools/*/ | tail -1)apksigner"
CERT="$("$APKSIGNER" verify --print-certs "$OUT/filemanager-${VERSION/+/-}.apk" | grep -i 'SHA-256 digest')"
grep -qi "bf5c6a0ee7245af4df724118b83be56c927188539e99c865749f652b34a2a6f1" <<<"$CERT" \
  || { echo "FAIL: APK is not signed with the upload key ($CERT)"; exit 1; }
(cd android && ./gradlew --stop >/dev/null 2>&1 || true)
echo "Release ready in $OUT"
