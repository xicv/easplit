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
  echo "Publishing requires a clean Git working tree." >&2
  exit 1
fi

gh auth status >/dev/null
SOURCE_COMMIT="$(/usr/bin/plutil -extract sourceCommit raw -o - "$MANIFEST")"
RELEASE_LABEL="$(/usr/bin/plutil -extract releaseLabel raw -o - "$MANIFEST")"
DMG_FILE="$(/usr/bin/plutil -extract dmgFile raw -o - "$MANIFEST")"
TAG="v$RELEASE_LABEL"

if [[ "$SOURCE_COMMIT" != "$(git rev-parse HEAD)" ]]; then
  echo "Manifest source commit does not match HEAD." >&2
  exit 1
fi

REMOTE_MAIN="$(git ls-remote origin refs/heads/main | /usr/bin/awk '{print $1}')"
if [[ "$REMOTE_MAIN" != "$SOURCE_COMMIT" ]]; then
  echo "Push the exact candidate commit to origin/main before publishing." >&2
  exit 1
fi

CHECK_CONCLUSION="$(gh api "repos/{owner}/{repo}/commits/$SOURCE_COMMIT/check-runs" \
  --jq '.check_runs[] | select(.name == "quality") | .conclusion' | /usr/bin/tail -1)"
if [[ "$CHECK_CONCLUSION" != "success" ]]; then
  echo "The hosted quality check is not successful for $SOURCE_COMMIT." >&2
  exit 1
fi

for file in "$DMG_FILE" "$DMG_FILE.sha256"; do
  if [[ "$file" == */* || ! -f "$RELEASE_DIR/$file" ]]; then
    echo "Missing release asset: $file" >&2
    exit 1
  fi
done

(
  cd "$RELEASE_DIR"
  /usr/bin/shasum -a 256 -c "$DMG_FILE.sha256"
)

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  if [[ "$(git rev-list -n 1 "$TAG")" != "$SOURCE_COMMIT" ]]; then
    echo "Existing tag $TAG does not identify the manifest commit." >&2
    exit 1
  fi
else
  git tag -a "$TAG" "$SOURCE_COMMIT" -m "eaSplit $RELEASE_LABEL"
fi

git push origin "$TAG"
gh release create "$TAG" \
  "$RELEASE_DIR/$DMG_FILE" \
  "$RELEASE_DIR/$DMG_FILE.sha256" \
  "$MANIFEST" \
  --prerelease \
  --verify-tag \
  --title "eaSplit $RELEASE_LABEL" \
  --notes "Signed and Apple-notarized eaSplit beta for macOS 15 or later. See the release manifest for exact source, build, notarization, and checksum provenance."

echo "Published GitHub release: $TAG ($SOURCE_COMMIT)"
