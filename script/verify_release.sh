#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /absolute/path/to/release-directory" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$1"
MANIFEST="$RELEASE_DIR/release-manifest.json"

if [[ "$RELEASE_DIR" != /* || ! -d "$RELEASE_DIR" || ! -f "$MANIFEST" ]]; then
  echo "Expected an absolute release directory containing release-manifest.json." >&2
  exit 2
fi

manifest_value() {
  /usr/bin/plutil -extract "$1" raw -o - "$MANIFEST"
}

SOURCE_COMMIT="$(manifest_value sourceCommit)"
RELEASE_LABEL="$(manifest_value releaseLabel)"
VERSION="$(manifest_value bundleVersion)"
BUILD="$(manifest_value buildNumber)"
DMG_FILE="$(manifest_value dmgFile)"
ZIP_FILE="$(manifest_value zipFile)"
DMG_SHA256="$(manifest_value dmgSHA256)"
ZIP_SHA256="$(manifest_value zipSHA256)"

for file in "$DMG_FILE" "$ZIP_FILE"; do
  if [[ "$file" == */* || "$file" != "$(/usr/bin/basename "$file")" ]]; then
    echo "Manifest contains an unsafe release filename: $file" >&2
    exit 1
  fi
done

DMG_PATH="$RELEASE_DIR/$DMG_FILE"
ZIP_PATH="$RELEASE_DIR/$ZIP_FILE"
DMG_STEM="${DMG_PATH%.dmg}"
APP_NOTARY_RESULT="$RELEASE_DIR/notarization.json"
APP_NOTARY_LOG="$RELEASE_DIR/notarization-log.json"
DMG_NOTARY_RESULT="$DMG_STEM-notarization.json"
DMG_NOTARY_LOG="$DMG_STEM-notarization-log.json"

for file in \
  "$DMG_PATH" "$DMG_PATH.sha256" \
  "$ZIP_PATH" "$ZIP_PATH.sha256" \
  "$APP_NOTARY_RESULT" "$APP_NOTARY_LOG" \
  "$DMG_NOTARY_RESULT" "$DMG_NOTARY_LOG"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing release evidence: $file" >&2
    exit 1
  fi
done

if [[ ! "$SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Manifest sourceCommit is not a full Git commit: $SOURCE_COMMIT" >&2
  exit 1
fi

if ! git -C "$ROOT_DIR" cat-file -e "$SOURCE_COMMIT^{commit}" 2>/dev/null; then
  echo "Manifest source commit is unavailable in this repository: $SOURCE_COMMIT" >&2
  exit 1
fi

(
  cd "$RELEASE_DIR"
  /usr/bin/shasum -a 256 -c "$DMG_FILE.sha256"
  /usr/bin/shasum -a 256 -c "$ZIP_FILE.sha256"
)

ACTUAL_DMG_SHA256="$(/usr/bin/shasum -a 256 "$DMG_PATH" | /usr/bin/awk '{print $1}')"
ACTUAL_ZIP_SHA256="$(/usr/bin/shasum -a 256 "$ZIP_PATH" | /usr/bin/awk '{print $1}')"
if [[ "$ACTUAL_DMG_SHA256" != "$DMG_SHA256" ]]; then
  echo "DMG checksum does not match release-manifest.json." >&2
  exit 1
fi
if [[ "$ACTUAL_ZIP_SHA256" != "$ZIP_SHA256" ]]; then
  echo "ZIP checksum does not match release-manifest.json." >&2
  exit 1
fi

EASPLIT_MANIFEST="$MANIFEST" \
EASPLIT_APP_NOTARY_RESULT="$APP_NOTARY_RESULT" \
EASPLIT_APP_NOTARY_LOG="$APP_NOTARY_LOG" \
EASPLIT_DMG_NOTARY_RESULT="$DMG_NOTARY_RESULT" \
EASPLIT_DMG_NOTARY_LOG="$DMG_NOTARY_LOG" \
/usr/bin/ruby <<'RUBY'
require "json"

manifest = JSON.parse(File.read(ENV.fetch("EASPLIT_MANIFEST")))

def verify_notarization(label, result_path, log_path, expected_id)
  result = JSON.parse(File.read(result_path))
  log = JSON.parse(File.read(log_path))
  abort("#{label} notarization result is not Accepted") unless result["status"] == "Accepted"
  abort("#{label} notarization ID does not match the manifest") unless result["id"] == expected_id
  abort("#{label} notarization log is not Accepted") unless log["status"] == "Accepted"
  unless log["statusSummary"] == "Ready for distribution"
    abort("#{label} notarization log is not ready for distribution")
  end
  issues = log["issues"]
  abort("#{label} notarization log contains issues") unless issues.nil? || issues.empty?
end

abort("Unsupported release manifest schema") unless manifest["schemaVersion"] == 1
abort("Unexpected product in release manifest") unless manifest["product"] == "eaSplit"
verify_notarization(
  "App",
  ENV.fetch("EASPLIT_APP_NOTARY_RESULT"),
  ENV.fetch("EASPLIT_APP_NOTARY_LOG"),
  manifest.fetch("appNotarizationId")
)
verify_notarization(
  "DMG",
  ENV.fetch("EASPLIT_DMG_NOTARY_RESULT"),
  ENV.fetch("EASPLIT_DMG_NOTARY_LOG"),
  manifest.fetch("dmgNotarizationId")
)
RUBY

/usr/bin/unzip -tq "$ZIP_PATH"
/usr/bin/codesign --verify --strict --verbose=2 "$DMG_PATH"
/usr/bin/hdiutil verify "$DMG_PATH"
/usr/bin/xcrun stapler validate "$DMG_PATH"
/usr/sbin/spctl --assess \
  --type open \
  --context context:primary-signature \
  --verbose=4 \
  "$DMG_PATH"

MOUNT_POINT="$(/usr/bin/mktemp -d -t easplit-release-mount)"
cleanup() {
  /usr/bin/hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
  /bin/rmdir "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup EXIT

/usr/bin/hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_POINT" "$DMG_PATH" >/dev/null

MOUNTED_APP="$MOUNT_POINT/eaSplit.app"
if [[ ! -d "$MOUNTED_APP" || ! -L "$MOUNT_POINT/Applications" ]]; then
  echo "Mounted DMG is missing eaSplit.app or the Applications shortcut." >&2
  exit 1
fi

"$ROOT_DIR/script/release_preflight.sh" "$MOUNTED_APP"
MOUNTED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MOUNTED_APP/Contents/Info.plist")"
MOUNTED_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$MOUNTED_APP/Contents/Info.plist")"
if [[ "$MOUNTED_VERSION" != "$VERSION" || "$MOUNTED_BUILD" != "$BUILD" ]]; then
  echo "Mounted app version $MOUNTED_VERSION ($MOUNTED_BUILD) does not match manifest $VERSION ($BUILD)." >&2
  exit 1
fi

cleanup
trap - EXIT
echo "Release verification passed: eaSplit $RELEASE_LABEL ($SOURCE_COMMIT)"
