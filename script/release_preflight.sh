#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /absolute/path/to/eaSplit.app" >&2
  exit 2
fi

APP_BUNDLE="$1"
EXPECTED_BUNDLE_ID="com.xicao.easplit"

if [[ "$APP_BUNDLE" != /* || "$APP_BUNDLE" != *.app || ! -d "$APP_BUNDLE" ]]; then
  echo "Expected an existing absolute .app path, found: $APP_BUNDLE" >&2
  exit 2
fi

INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Missing Info.plist: $INFO_PLIST" >&2
  exit 1
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
if [[ "$BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]]; then
  echo "Expected bundle identifier $EXPECTED_BUNDLE_ID, found $BUNDLE_ID" >&2
  exit 1
fi

EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
if [[ ! -x "$APP_BINARY" ]]; then
  echo "Missing executable: $APP_BINARY" >&2
  exit 1
fi

ARCHITECTURES="$(/usr/bin/lipo -archs "$APP_BINARY")"
if [[ " $ARCHITECTURES " != *" arm64 "* || " $ARCHITECTURES " != *" x86_64 "* ]]; then
  echo "Release must contain arm64 and x86_64; found: $ARCHITECTURES" >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

SIGNATURE_DETAILS="$(/usr/bin/codesign -dvvv "$APP_BUNDLE" 2>&1)"
if ! /usr/bin/grep -q '^Authority=Developer ID Application:' <<<"$SIGNATURE_DETAILS"; then
  echo "Release is not signed with a Developer ID Application certificate." >&2
  exit 1
fi

if ! /usr/bin/grep -Eq '^CodeDirectory .*flags=.*\(runtime\)' <<<"$SIGNATURE_DETAILS"; then
  echo "Release is missing Hardened Runtime." >&2
  exit 1
fi

ENTITLEMENTS_FILE="$(/usr/bin/mktemp -t easplit-entitlements)"
trap '/bin/rm -f "$ENTITLEMENTS_FILE"' EXIT
/usr/bin/codesign -d --entitlements "$ENTITLEMENTS_FILE" "$APP_BUNDLE" 2>/dev/null || true

GET_TASK_ALLOW="$(/usr/bin/plutil -extract com.apple.security.get-task-allow raw -o - "$ENTITLEMENTS_FILE" 2>/dev/null || true)"
if [[ "$GET_TASK_ALLOW" == "true" ]]; then
  echo "Release contains the development-only get-task-allow entitlement." >&2
  exit 1
fi

APP_SANDBOX="$(/usr/bin/plutil -extract com.apple.security.app-sandbox raw -o - "$ENTITLEMENTS_FILE" 2>/dev/null || true)"
if [[ "$APP_SANDBOX" == "true" ]]; then
  echo "Release unexpectedly enables App Sandbox, which prevents eaSplit's Accessibility workflow." >&2
  exit 1
fi

/usr/bin/xcrun stapler validate "$APP_BUNDLE"
/usr/sbin/spctl --assess --type execute --verbose=4 "$APP_BUNDLE"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
echo "Release preflight passed for eaSplit $VERSION ($BUILD), architectures: $ARCHITECTURES"
