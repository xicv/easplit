#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_BINARY="$ROOT_DIR/.build/acceptance-fixture/Build/Products/Debug/eaSplit Acceptance Fixture.app/Contents/MacOS/eaSplit Acceptance Fixture"

fixture_pids() {
  /usr/bin/pgrep -f "$FIXTURE_BINARY" 2>/dev/null || true
}

stop_fixture() {
  while IFS= read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] && /bin/kill "$pid" 2>/dev/null || true
  done < <(fixture_pids)
}

stop_fixture
"$ROOT_DIR/script/run_acceptance_fixture.sh"
trap stop_fixture EXIT

for _ in {1..100}; do
  [[ -n "$(fixture_pids)" ]] && break
  sleep 0.1
done

if [[ -z "$(fixture_pids)" ]]; then
  echo "The acceptance fixture did not launch" >&2
  exit 1
fi

"$ROOT_DIR/script/build_and_run.sh" --acceptance
echo "Real-window acceptance passed. Evidence: $ROOT_DIR/.build/acceptance/report.json"
