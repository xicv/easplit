#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.build/acceptance-fixture"
FIXTURE_APP="$DERIVED_DATA/Build/Products/Debug/eaSplit Acceptance Fixture.app"
MACHINE_ARCH="$(/usr/bin/uname -m)"

for command in xcodebuild xcodegen; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command is unavailable: $command" >&2
    exit 1
  fi
done

xcodegen generate --spec "$ROOT_DIR/project.yml" --project "$ROOT_DIR"
xcodebuild \
  -project "$ROOT_DIR/eaSplit.xcodeproj" \
  -scheme eaSplitAcceptanceFixture \
  -configuration Debug \
  -destination "platform=macOS,arch=$MACHINE_ARCH" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  -quiet \
  build

/usr/bin/open "$FIXTURE_APP"
echo "Opened: $FIXTURE_APP"
