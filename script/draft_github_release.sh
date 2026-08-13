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

cd "$ROOT_DIR"
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  echo "Drafting requires a clean Git working tree." >&2
  exit 1
fi

gh auth status >/dev/null
SOURCE_COMMIT="$(/usr/bin/plutil -extract sourceCommit raw -o - "$MANIFEST")"
RELEASE_LABEL="$(/usr/bin/plutil -extract releaseLabel raw -o - "$MANIFEST")"
DMG_FILE="$(/usr/bin/plutil -extract dmgFile raw -o - "$MANIFEST")"
TAG="v$RELEASE_LABEL"
RELEASE_NOTES="$ROOT_DIR/docs/releases/$RELEASE_LABEL.md"

/usr/bin/ruby "$ROOT_DIR/script/release_candidate_contract.rb" \
  "$RELEASE_LABEL" \
  "$SOURCE_COMMIT" >/dev/null
"$ROOT_DIR/script/verify_release.sh" "$RELEASE_DIR"

if [[ "$SOURCE_COMMIT" != "$(git rev-parse HEAD)" ]]; then
  echo "Manifest source commit does not match HEAD." >&2
  exit 1
fi

REMOTE_MAIN="$(git ls-remote origin refs/heads/main | /usr/bin/awk '{print $1}')"
if [[ "$REMOTE_MAIN" != "$SOURCE_COMMIT" ]]; then
  echo "The exact candidate commit must be present at origin/main before drafting." >&2
  exit 1
fi

QUALITY_SUCCEEDED="$(gh api "repos/{owner}/{repo}/commits/$SOURCE_COMMIT/check-runs?per_page=100" \
  --jq '[.check_runs[] | select(.name == "quality")] | sort_by(.id) | last | (.status == "completed" and .conclusion == "success")')"
if [[ "$QUALITY_SUCCEEDED" != "true" ]]; then
  echo "The hosted quality check is not successful for $SOURCE_COMMIT." >&2
  exit 1
fi

if [[ -n "$(git ls-remote --tags origin "refs/tags/$TAG" "refs/tags/$TAG^{}")" ]]; then
  echo "Remote tag already exists: $TAG" >&2
  exit 1
fi
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "GitHub release already exists: $TAG" >&2
  exit 1
fi

DMG_PATH="$RELEASE_DIR/$DMG_FILE"
CHECKSUM_PATH="$DMG_PATH.sha256"
RELEASE_URL="$(gh release create "$TAG" \
  "$DMG_PATH" \
  "$CHECKSUM_PATH" \
  "$MANIFEST" \
  --draft \
  --prerelease \
  --latest=false \
  --target "$SOURCE_COMMIT" \
  --title "eaSplit $RELEASE_LABEL" \
  --notes-file "$RELEASE_NOTES")"

RELEASE_JSON="$(gh release view "$TAG" \
  --json isDraft,isPrerelease,tagName,targetCommitish,url,assets)"
EASPLIT_DRAFT_JSON="$RELEASE_JSON" \
EASPLIT_EXPECTED_TAG="$TAG" \
EASPLIT_EXPECTED_COMMIT="$SOURCE_COMMIT" \
EASPLIT_EXPECTED_DMG="$DMG_FILE" \
/usr/bin/ruby <<'RUBY'
require "json"

release = JSON.parse(ENV.fetch("EASPLIT_DRAFT_JSON"))
abort("Release was not retained as a draft") unless release.fetch("isDraft")
abort("Release was not marked as a prerelease") unless release.fetch("isPrerelease")
abort("Draft release tag is incorrect") unless release.fetch("tagName") == ENV.fetch("EASPLIT_EXPECTED_TAG")
unless release.fetch("targetCommitish") == ENV.fetch("EASPLIT_EXPECTED_COMMIT")
  abort("Draft release target is not the exact candidate commit")
end

expected_assets = [
  ENV.fetch("EASPLIT_EXPECTED_DMG"),
  "#{ENV.fetch('EASPLIT_EXPECTED_DMG')}.sha256",
  "release-manifest.json",
].sort
assets = release.fetch("assets")
abort("Draft release contains unexpected assets") unless assets.map { |asset| asset.fetch("name") }.sort == expected_assets
abort("A draft release asset is empty") unless assets.all? { |asset| asset.fetch("size").positive? }
RUBY

echo "Unpublished GitHub draft ready: $RELEASE_URL"
