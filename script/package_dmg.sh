#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 /absolute/path/to/eaSplit.app /absolute/path/to/eaSplit.dmg" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$1"
OUTPUT_DMG="$2"
NOTARY_PROFILE="${EASPLIT_NOTARY_PROFILE:-}"
SIGNING_IDENTITY="${EASPLIT_DEVELOPER_ID:-Developer ID Application: XI CAO (6UVB8NWW6F)}"

if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "Set EASPLIT_NOTARY_PROFILE to a notarytool keychain profile name." >&2
  exit 1
fi

if [[ "$APP_BUNDLE" != /* || "$APP_BUNDLE" != *.app || ! -d "$APP_BUNDLE" ]]; then
  echo "Expected an existing absolute .app path, found: $APP_BUNDLE" >&2
  exit 2
fi

if [[ "$OUTPUT_DMG" != /* || "$OUTPUT_DMG" != *.dmg ]]; then
  echo "Expected an absolute .dmg output path, found: $OUTPUT_DMG" >&2
  exit 2
fi

if [[ -e "$OUTPUT_DMG" ]]; then
  echo "Refusing to replace an existing disk image: $OUTPUT_DMG" >&2
  exit 1
fi

AVAILABLE_IDENTITIES="$(/usr/bin/security find-identity -v -p codesigning)"
if ! /usr/bin/grep -Fq "\"$SIGNING_IDENTITY\"" <<<"$AVAILABLE_IDENTITIES"; then
  echo "Developer ID signing identity is unavailable: $SIGNING_IDENTITY" >&2
  exit 1
fi

OUTPUT_DIR="$(/usr/bin/dirname "$OUTPUT_DMG")"
if [[ ! -d "$OUTPUT_DIR" ]]; then
  echo "Output directory does not exist: $OUTPUT_DIR" >&2
  exit 1
fi

DMG_STEM="${OUTPUT_DMG%.dmg}"
NOTARY_RESULT="$DMG_STEM-notarization.json"
NOTARY_LOG="$DMG_STEM-notarization-log.json"
CHECKSUM_FILE="$OUTPUT_DMG.sha256"
STAGING_DIR="$(/usr/bin/mktemp -d -t easplit-dmg)"
cleanup() {
  /bin/rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

"$ROOT_DIR/script/release_preflight.sh" "$APP_BUNDLE"

/usr/bin/ditto "$APP_BUNDLE" "$STAGING_DIR/eaSplit.app"
/bin/ln -s /Applications "$STAGING_DIR/Applications"

/usr/bin/hdiutil create \
  -volname "eaSplit" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$OUTPUT_DMG"

/usr/bin/codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$OUTPUT_DMG"
/usr/bin/codesign --verify --strict --verbose=2 "$OUTPUT_DMG"
/usr/bin/hdiutil verify "$OUTPUT_DMG"
/usr/bin/xcrun notarytool submit "$OUTPUT_DMG" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait \
  --output-format json >"$NOTARY_RESULT"

NOTARY_STATUS="$(/usr/bin/plutil -extract status raw -o - "$NOTARY_RESULT")"
NOTARY_ID="$(/usr/bin/plutil -extract id raw -o - "$NOTARY_RESULT")"
if [[ "$NOTARY_STATUS" != "Accepted" ]]; then
  echo "Disk image notarization $NOTARY_ID finished with status: $NOTARY_STATUS" >&2
  exit 1
fi

/usr/bin/xcrun notarytool log "$NOTARY_ID" \
  --keychain-profile "$NOTARY_PROFILE" \
  "$NOTARY_LOG"
/usr/bin/xcrun stapler staple "$OUTPUT_DMG"
/usr/bin/xcrun stapler validate "$OUTPUT_DMG"
/usr/sbin/spctl --assess \
  --type open \
  --context context:primary-signature \
  --verbose=4 \
  "$OUTPUT_DMG"

(
  cd "$OUTPUT_DIR"
  /usr/bin/shasum -a 256 "$(/usr/bin/basename "$OUTPUT_DMG")" \
    >"$(/usr/bin/basename "$CHECKSUM_FILE")"
)

echo "Disk image ready: $OUTPUT_DMG"
echo "Checksum: $CHECKSUM_FILE"
echo "Notarization submission: $NOTARY_ID"
