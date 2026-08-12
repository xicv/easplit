#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="eaSplit"
BUNDLE_ID="com.xicao.easplit.debug"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.build/DerivedData"
BUILT_APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
RUN_APP_BUNDLE="/Users/xicao/Applications/eaSplit Development.app"
APP_BINARY="$RUN_APP_BUNDLE/Contents/MacOS/$APP_NAME"
LAUNCH_SERVICES_REGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

case "$MODE" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify) ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

running_development_pids() {
  /usr/bin/pgrep -f "$APP_BINARY" 2>/dev/null || true
}

while IFS= read -r pid; do
  [[ "$pid" =~ ^[0-9]+$ ]] && /bin/kill "$pid"
done < <(running_development_pids)

for _ in {1..50}; do
  if [[ -z "$(running_development_pids)" ]]; then
    break
  fi
  sleep 0.1
done

if [[ -n "$(running_development_pids)" ]]; then
  echo "Timed out waiting for eaSplit Development to stop" >&2
  exit 1
fi

xcodegen generate --spec "$ROOT_DIR/project.yml" --project "$ROOT_DIR"
xcodebuild \
  -project "$ROOT_DIR/eaSplit.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  build

ACTUAL_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$BUILT_APP_BUNDLE/Contents/Info.plist")"
if [[ "$ACTUAL_BUNDLE_ID" != "$BUNDLE_ID" ]]; then
  echo "Expected bundle identifier $BUNDLE_ID, found $ACTUAL_BUNDLE_ID" >&2
  exit 1
fi

if [[ "$RUN_APP_BUNDLE" != "/Users/xicao/Applications/eaSplit Development.app" ]]; then
  echo "Refusing to replace an unexpected application path: $RUN_APP_BUNDLE" >&2
  exit 1
fi

STAGING_DIRECTORY="$(mktemp -d '/Users/xicao/Applications/.easplit-stage.XXXXXX')"
trap '/bin/rm -rf "$STAGING_DIRECTORY"' EXIT
/usr/bin/ditto "$BUILT_APP_BUNDLE" "$STAGING_DIRECTORY/eaSplit Development.app"
/bin/rm -rf "/Users/xicao/Applications/eaSplit Development.app"
/bin/mv "$STAGING_DIRECTORY/eaSplit Development.app" "$RUN_APP_BUNDLE"
/bin/rmdir "$STAGING_DIRECTORY"
trap - EXIT

/usr/bin/codesign --verify --deep --strict "$RUN_APP_BUNDLE"
"$LAUNCH_SERVICES_REGISTER" -f -R -trusted "$RUN_APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$RUN_APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    [[ -n "$(running_development_pids)" ]]
    ;;
esac
