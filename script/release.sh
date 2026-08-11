#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/eaSplit.xcodeproj"
EXPORT_OPTIONS="$ROOT_DIR/script/ExportOptions.plist"
NOTARY_PROFILE="${EASPLIT_NOTARY_PROFILE:-}"
TIMESTAMP="$(/bin/date -u '+%Y%m%dT%H%M%SZ')"
RELEASE_DIR="$ROOT_DIR/.build/releases/$TIMESTAMP"
ARCHIVE_PATH="$RELEASE_DIR/eaSplit.xcarchive"
EXPORT_DIR="$RELEASE_DIR/export"
UPLOAD_ZIP="$RELEASE_DIR/eaSplit-notarization.zip"
FINAL_ZIP="$RELEASE_DIR/eaSplit.zip"
NOTARY_RESULT="$RELEASE_DIR/notarization.json"
NOTARY_LOG="$RELEASE_DIR/notarization-log.json"

if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "Set EASPLIT_NOTARY_PROFILE to a notarytool keychain profile name." >&2
  exit 1
fi

if [[ -e "$RELEASE_DIR" ]]; then
  echo "Refusing to replace an existing release directory: $RELEASE_DIR" >&2
  exit 1
fi

/bin/mkdir -p "$RELEASE_DIR"

xcodegen generate --spec "$ROOT_DIR/project.yml" --project "$ROOT_DIR"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme eaSplit \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  archive

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

EXPORTED_APP="$EXPORT_DIR/eaSplit.app"
if [[ ! -d "$EXPORTED_APP" ]]; then
  echo "Archive export did not produce $EXPORTED_APP" >&2
  exit 1
fi

/usr/bin/ditto -c -k --keepParent "$EXPORTED_APP" "$UPLOAD_ZIP"
/usr/bin/xcrun notarytool submit "$UPLOAD_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait \
  --output-format json >"$NOTARY_RESULT"

NOTARY_STATUS="$(/usr/bin/plutil -extract status raw -o - "$NOTARY_RESULT")"
NOTARY_ID="$(/usr/bin/plutil -extract id raw -o - "$NOTARY_RESULT")"
if [[ "$NOTARY_STATUS" != "Accepted" ]]; then
  echo "Notarization $NOTARY_ID finished with status: $NOTARY_STATUS" >&2
  exit 1
fi

/usr/bin/xcrun notarytool log "$NOTARY_ID" \
  --keychain-profile "$NOTARY_PROFILE" \
  "$NOTARY_LOG"
/usr/bin/xcrun stapler staple "$EXPORTED_APP"

"$ROOT_DIR/script/release_preflight.sh" "$EXPORTED_APP"

/usr/bin/ditto -c -k --keepParent "$EXPORTED_APP" "$FINAL_ZIP"
(
  cd "$RELEASE_DIR"
  /usr/bin/shasum -a 256 "$(/usr/bin/basename "$FINAL_ZIP")" >"$(/usr/bin/basename "$FINAL_ZIP").sha256"
)

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$EXPORTED_APP/Contents/Info.plist")"
FINAL_DMG="$RELEASE_DIR/eaSplit-$VERSION.dmg"
"$ROOT_DIR/script/package_dmg.sh" "$EXPORTED_APP" "$FINAL_DMG"

echo "Release ready: $FINAL_ZIP"
echo "Checksum: $FINAL_ZIP.sha256"
echo "Notarization submission: $NOTARY_ID"
echo "Installer ready: $FINAL_DMG"
echo "Installer checksum: $FINAL_DMG.sha256"
