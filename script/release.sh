#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/eaSplit.xcodeproj"
EXPORT_OPTIONS="$ROOT_DIR/script/ExportOptions.plist"
NOTARY_PROFILE="${EASPLIT_NOTARY_PROFILE:-}"
RELEASE_LABEL="${EASPLIT_RELEASE_LABEL:-}"
TIMESTAMP="$(/bin/date -u '+%Y%m%dT%H%M%SZ')"
RELEASE_DIR="$ROOT_DIR/.build/releases/$TIMESTAMP"
ARCHIVE_PATH="$RELEASE_DIR/eaSplit.xcarchive"
EXPORT_DIR="$RELEASE_DIR/export"
UPLOAD_ZIP="$RELEASE_DIR/eaSplit-notarization.zip"
NOTARY_RESULT="$RELEASE_DIR/notarization.json"
NOTARY_LOG="$RELEASE_DIR/notarization-log.json"
MANIFEST="$RELEASE_DIR/release-manifest.json"
MANIFEST_PLIST="$RELEASE_DIR/release-manifest.plist"

if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "Set EASPLIT_NOTARY_PROFILE to a notarytool keychain profile name." >&2
  exit 1
fi

cd "$ROOT_DIR"
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  echo "Release requires a clean Git working tree." >&2
  exit 1
fi

SOURCE_COMMIT="$(git rev-parse --verify HEAD)"
EASPLIT_LINT_BASE="${EASPLIT_LINT_BASE:-HEAD^}" "$ROOT_DIR/script/quality.sh"

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

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$EXPORTED_APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$EXPORTED_APP/Contents/Info.plist")"
RELEASE_LABEL="${RELEASE_LABEL:-$VERSION}"
if [[ ! "$RELEASE_LABEL" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid release label: $RELEASE_LABEL" >&2
  exit 1
fi

FINAL_ZIP="$RELEASE_DIR/eaSplit-$RELEASE_LABEL.zip"
/usr/bin/ditto -c -k --keepParent "$EXPORTED_APP" "$FINAL_ZIP"
(
  cd "$RELEASE_DIR"
  /usr/bin/shasum -a 256 "$(/usr/bin/basename "$FINAL_ZIP")" >"$(/usr/bin/basename "$FINAL_ZIP").sha256"
)

FINAL_DMG="$RELEASE_DIR/eaSplit-$RELEASE_LABEL.dmg"
"$ROOT_DIR/script/package_dmg.sh" "$EXPORTED_APP" "$FINAL_DMG"

DMG_NOTARY_RESULT="${FINAL_DMG%.dmg}-notarization.json"
DMG_NOTARY_ID="$(/usr/bin/plutil -extract id raw -o - "$DMG_NOTARY_RESULT")"
ZIP_SHA256="$(/usr/bin/awk '{print $1}' "$FINAL_ZIP.sha256")"
DMG_SHA256="$(/usr/bin/awk '{print $1}' "$FINAL_DMG.sha256")"
XCODE_VERSION="$(xcodebuild -version | /usr/bin/paste -sd ';' -)"
XCODEGEN_VERSION="$(xcodegen --version)"
SWIFTLINT_VERSION="$(swiftlint version)"

/usr/bin/plutil -create xml1 "$MANIFEST_PLIST"
/usr/bin/plutil -insert schemaVersion -integer 1 "$MANIFEST_PLIST"
/usr/bin/plutil -insert product -string eaSplit "$MANIFEST_PLIST"
/usr/bin/plutil -insert releaseLabel -string "$RELEASE_LABEL" "$MANIFEST_PLIST"
/usr/bin/plutil -insert bundleVersion -string "$VERSION" "$MANIFEST_PLIST"
/usr/bin/plutil -insert buildNumber -string "$BUILD" "$MANIFEST_PLIST"
/usr/bin/plutil -insert sourceCommit -string "$SOURCE_COMMIT" "$MANIFEST_PLIST"
/usr/bin/plutil -insert createdAt -string "$TIMESTAMP" "$MANIFEST_PLIST"
/usr/bin/plutil -insert xcodeVersion -string "$XCODE_VERSION" "$MANIFEST_PLIST"
/usr/bin/plutil -insert xcodegenVersion -string "$XCODEGEN_VERSION" "$MANIFEST_PLIST"
/usr/bin/plutil -insert swiftlintVersion -string "$SWIFTLINT_VERSION" "$MANIFEST_PLIST"
/usr/bin/plutil -insert appNotarizationId -string "$NOTARY_ID" "$MANIFEST_PLIST"
/usr/bin/plutil -insert dmgNotarizationId -string "$DMG_NOTARY_ID" "$MANIFEST_PLIST"
/usr/bin/plutil -insert zipFile -string "$(/usr/bin/basename "$FINAL_ZIP")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert zipSHA256 -string "$ZIP_SHA256" "$MANIFEST_PLIST"
/usr/bin/plutil -insert dmgFile -string "$(/usr/bin/basename "$FINAL_DMG")" "$MANIFEST_PLIST"
/usr/bin/plutil -insert dmgSHA256 -string "$DMG_SHA256" "$MANIFEST_PLIST"
/usr/bin/plutil -convert json -o "$MANIFEST" "$MANIFEST_PLIST"
/bin/rm "$MANIFEST_PLIST"

echo "Release ready: $FINAL_ZIP"
echo "Checksum: $FINAL_ZIP.sha256"
echo "Notarization submission: $NOTARY_ID"
echo "Installer ready: $FINAL_DMG"
echo "Installer checksum: $FINAL_DMG.sha256"
echo "Release manifest: $MANIFEST"
