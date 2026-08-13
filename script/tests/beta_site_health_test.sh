#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HEALTH_SCRIPT="$ROOT_DIR/script/beta_site_health.sh"
FIXTURE_ROOT="$(mktemp -d -t easplit-beta-health-test)"
SERVER_PID=""

cleanup() {
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$FIXTURE_ROOT"
}
trap cleanup EXIT

PORT="$(python3 - <<'PY'
import socket

with socket.socket() as listener:
    listener.bind(("127.0.0.1", 0))
    print(listener.getsockname()[1])
PY
)"
SITE_URL="http://127.0.0.1:$PORT"
TAG="v0.1.0-beta.4"
DMG_FILE="eaSplit-0.1.0-beta.4.dmg"
RELEASE_DIR="$FIXTURE_ROOT/releases/download/$TAG"
DMG_URL="$SITE_URL/releases/download/$TAG/$DMG_FILE"
RELEASE_API_DIR="$FIXTURE_ROOT/api/releases/tags"
RELEASE_API_URL="$SITE_URL/api/releases/tags/$TAG"
FEEDBACK_URL="https://example.test/easplit-feedback"

hash_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

run_health() {
  local mode="${1:-full}"
  EASPLIT_BETA_SITE_URL="$SITE_URL" \
  EASPLIT_BETA_RELEASE_PREFIX="$SITE_URL/releases/download" \
  EASPLIT_BETA_RELEASE_API_URL="$RELEASE_API_URL" \
  EASPLIT_BETA_FEEDBACK_URL="$FEEDBACK_URL" \
  EASPLIT_BETA_VERIFY_MODE="$mode" \
  EASPLIT_CURL_RETRY=0 \
    "$HEALTH_SCRIPT"
}

mkdir -p "$RELEASE_DIR" "$RELEASE_API_DIR"
printf 'not a real disk image; deterministic health-check fixture\n' >"$RELEASE_DIR/$DMG_FILE"
DMG_SHA256="$(hash_file "$RELEASE_DIR/$DMG_FILE")"
printf '%s  %s\n' "$DMG_SHA256" "$DMG_FILE" >"$RELEASE_DIR/$DMG_FILE.sha256"
printf '%s\n' \
  '{' \
  '  "schemaVersion": 1,' \
  '  "sourceCommit": "393531df10d7c9911ca39f73ff2a71656a9d2c27",' \
  '  "releaseLabel": "0.1.0-beta.4",' \
  '  "product": "eaSplit",' \
  '  "dmgSHA256": "'"$DMG_SHA256"'",' \
  '  "dmgFile": "eaSplit-0.1.0-beta.4.dmg",' \
  '  "appNotarizationId": "ad01d41c-c64a-4a34-b800-774db28b8202",' \
  '  "dmgNotarizationId": "416f44ea-9e6b-428b-bbfa-bbbff39216b8"' \
  '}' >"$RELEASE_DIR/release-manifest.json"
printf '%s\n' \
  '{' \
  '  "tag_name": "v0.1.0-beta.4",' \
  '  "draft": false,' \
  '  "assets": [' \
  '    {' \
  '      "name": "eaSplit-0.1.0-beta.4.dmg",' \
  '      "state": "uploaded",' \
  '      "size": 55,' \
  '      "digest": "sha256:'"$DMG_SHA256"'",' \
  '      "browser_download_url": "'"$DMG_URL"'"' \
  '    },' \
  '    {' \
  '      "name": "eaSplit-0.1.0-beta.4.dmg.sha256",' \
  '      "state": "uploaded",' \
  '      "size": 96,' \
  '      "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",' \
  '      "browser_download_url": "'"$DMG_URL"'.sha256"' \
  '    },' \
  '    {' \
  '      "name": "release-manifest.json",' \
  '      "state": "uploaded",' \
  '      "size": 512,' \
  '      "digest": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",' \
  '      "browser_download_url": "'"${DMG_URL%/*}"'/release-manifest.json"' \
  '    }' \
  '  ]' \
  '}' >"$RELEASE_API_DIR/$TAG"

for page in index.html privacy.html support.html terms.html; do
  printf '<!doctype html><html><body><a href="%s">Download</a></body></html>\n' \
    "$DMG_URL" >"$FIXTURE_ROOT/$page"
done
printf '<!doctype html><html><body><a href="%s">Download</a><a href="%s">Feedback</a></body></html>\n' \
  "$DMG_URL" "$FEEDBACK_URL" >"$FIXTURE_ROOT/support.html"
printf '<!doctype html><html><body><a href="%s">Download</a><a href="%s.sha256">Checksum</a></body></html>\n' \
  "$DMG_URL" "$DMG_URL" >"$FIXTURE_ROOT/install.html"

python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$FIXTURE_ROOT" \
  >"$FIXTURE_ROOT/server.log" 2>&1 &
SERVER_PID=$!

for _ in {1..40}; do
  if curl --fail --silent "$SITE_URL/install.html" >/dev/null; then
    break
  fi
  sleep 0.05
done

if [[ ! -x "$HEALTH_SCRIPT" ]]; then
  echo "Expected executable health script: $HEALTH_SCRIPT" >&2
  exit 1
fi

run_health

echo "beta_site_health_test: happy path passed"

printf 'tampered release bytes\n' >"$RELEASE_DIR/$DMG_FILE"
if run_health >"$FIXTURE_ROOT/tampered.log" 2>&1; then
  echo "Expected tampered release bytes to fail verification." >&2
  exit 1
fi

echo "beta_site_health_test: tampered artifact rejected"

run_health metadata
echo "beta_site_health_test: metadata mode avoids downloading DMG bytes"

printf 'not a real disk image; deterministic health-check fixture\n' >"$RELEASE_DIR/$DMG_FILE"
printf '<!doctype html><html><body><a href="%s">Download</a><a href="missing.html">Broken</a></body></html>\n' \
  "$DMG_URL" >"$FIXTURE_ROOT/index.html"
if run_health >"$FIXTURE_ROOT/broken-link.log" 2>&1; then
  echo "Expected a broken internal link to fail verification." >&2
  exit 1
fi

echo "beta_site_health_test: broken internal link rejected"

printf '<!doctype html><html><body><a href="%s">Download</a></body></html>\n' \
  "$DMG_URL" >"$FIXTURE_ROOT/index.html"
printf '<!doctype html><html><body><a href="%s">Download</a></body></html>\n' \
  "$DMG_URL" >"$FIXTURE_ROOT/support.html"
if run_health >"$FIXTURE_ROOT/missing-feedback.log" 2>&1; then
  echo "Expected a missing feedback action to fail verification." >&2
  exit 1
fi

echo "beta_site_health_test: missing feedback action rejected"
