#!/usr/bin/env bash
set -euo pipefail

SITE_URL="${EASPLIT_BETA_SITE_URL:-https://xicv.github.io/easplit}"
RELEASE_PREFIX="${EASPLIT_BETA_RELEASE_PREFIX:-https://github.com/xicv/easplit/releases/download}"
FEEDBACK_URL="${EASPLIT_BETA_FEEDBACK_URL:-https://github.com/xicv/easplit/issues/new?template=beta-feedback.yml}"
GITHUB_TOKEN="${EASPLIT_GITHUB_TOKEN:-}"
VERIFY_MODE="${EASPLIT_BETA_VERIFY_MODE:-full}"
CURL_RETRY="${EASPLIT_CURL_RETRY:-3}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/easplit-beta-health.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

SITE_URL="${SITE_URL%/}"
RELEASE_PREFIX="${RELEASE_PREFIX%/}"
CURL=(curl --fail --location --show-error --silent --retry "$CURL_RETRY" --connect-timeout 15 --max-time 180)
PAGES=(index.html install.html privacy.html support.html terms.html)

for command in curl jq; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "beta_site_health.sh requires $command." >&2
    exit 2
  fi
done

if [[ "$VERIFY_MODE" != "full" && "$VERIFY_MODE" != "metadata" ]]; then
  echo "EASPLIT_BETA_VERIFY_MODE must be full or metadata." >&2
  exit 2
fi

for page in "${PAGES[@]}"; do
  "${CURL[@]}" "$SITE_URL/$page" --output "$WORK_DIR/$page"
  printf 'PASS page %s\n' "$SITE_URL/$page"
done

if ! grep -Fq "href=\"$FEEDBACK_URL\"" "$WORK_DIR/support.html"; then
  echo "The support page is missing the beta feedback action: $FEEDBACK_URL" >&2
  exit 1
fi
printf 'PASS support page exposes the beta feedback action\n'

REFERENCES="$WORK_DIR/references.txt"
grep -hEo '(href|src)="[^"]+"' "$WORK_DIR"/*.html \
  | sed -E 's/^(href|src)="|"$//g' \
  | sort -u >"$REFERENCES" || true

INTERNAL_REFERENCE_COUNT=0
while IFS= read -r reference; do
  reference="${reference%%#*}"
  [[ -z "$reference" ]] && continue
  case "$reference" in
    http://* | https://* | mailto:* | data:*)
      continue
      ;;
  esac

  if [[ "$reference" == /* ]]; then
    if [[ "$SITE_URL" =~ ^(https?://[^/]+) ]]; then
      reference_url="${BASH_REMATCH[1]}$reference"
    else
      echo "Unable to resolve root-relative URL: $reference" >&2
      exit 1
    fi
  else
    reference_url="$SITE_URL/$reference"
  fi

  if ! "${CURL[@]}" "$reference_url" --output /dev/null; then
    echo "Broken internal website reference: $reference_url" >&2
    exit 1
  fi
  INTERNAL_REFERENCE_COUNT=$((INTERNAL_REFERENCE_COUNT + 1))
done <"$REFERENCES"

printf 'PASS %s internal navigation and asset references\n' "$INTERNAL_REFERENCE_COUNT"

DOWNLOAD_LINKS="$WORK_DIR/download-links.txt"
grep -hEo 'href="[^"]+\.dmg"' "$WORK_DIR/index.html" "$WORK_DIR/install.html" \
  | sed -E 's/^href="|"$//g' \
  | sort -u >"$DOWNLOAD_LINKS" || true

if [[ "$(wc -l <"$DOWNLOAD_LINKS" | tr -d ' ')" -ne 1 ]]; then
  echo "Expected every public DMG button to identify one release artifact." >&2
  exit 1
fi

DMG_URL="$(head -n 1 "$DOWNLOAD_LINKS")"
if [[ "$DMG_URL" != "$RELEASE_PREFIX/"* ]]; then
  echo "The public DMG link is outside the expected release: $DMG_URL" >&2
  exit 1
fi
if [[ ! "$DMG_URL" =~ ^https?://.*/releases/download/(v[^/]+)/([^/]+\.dmg)$ ]]; then
  echo "The public DMG link is not a versioned GitHub Release URL: $DMG_URL" >&2
  exit 1
fi
TAG="${BASH_REMATCH[1]}"
DMG_FILE="${BASH_REMATCH[2]}"

CHECKSUM_URL="$(grep -Eo 'href="[^"]+\.dmg\.sha256"' "$WORK_DIR/install.html" \
  | sed -E 's/^href="|"$//g' \
  | head -n 1 || true)"
if [[ "$CHECKSUM_URL" != "$DMG_URL.sha256" ]]; then
  echo "The install page checksum does not match the advertised DMG." >&2
  exit 1
fi

printf 'PASS one versioned artifact is advertised: %s\n' "$DMG_URL"
printf 'PASS checksum link matches the advertised artifact\n'

RELEASE_ASSET_BASE="${DMG_URL%/*}"
MANIFEST_URL="$RELEASE_ASSET_BASE/release-manifest.json"

if [[ "$VERIFY_MODE" == "metadata" ]]; then
  RELEASE_API_URL="${EASPLIT_BETA_RELEASE_API_URL:-https://api.github.com/repos/xicv/easplit/releases/tags/$TAG}"
  RELEASE_METADATA="$WORK_DIR/release-metadata.json"
  API_CURL=("${CURL[@]}" \
    --header "Accept: application/vnd.github+json" \
    --header "User-Agent: eaSplit-beta-health")
  if [[ -n "$GITHUB_TOKEN" ]]; then
    API_CURL+=(--header "Authorization: Bearer $GITHUB_TOKEN")
  fi
  "${API_CURL[@]}" "$RELEASE_API_URL" --output "$RELEASE_METADATA"

  jq --exit-status \
    --arg tag "$TAG" \
    --arg dmgFile "$DMG_FILE" \
    --arg dmgURL "$DMG_URL" \
    --arg checksumFile "$DMG_FILE.sha256" \
    --arg checksumURL "$CHECKSUM_URL" \
    --arg manifestURL "$MANIFEST_URL" \
    '
      def uploaded_asset($name; $url):
        [.assets[] | select(
          .name == $name and
          .browser_download_url == $url and
          .state == "uploaded" and
          .size > 0 and
          (.digest | test("^sha256:[0-9a-f]{64}$"))
        )] | length == 1;

      .tag_name == $tag and
      .draft == false and
      uploaded_asset($dmgFile; $dmgURL) and
      uploaded_asset($checksumFile; $checksumURL) and
      uploaded_asset("release-manifest.json"; $manifestURL)
    ' "$RELEASE_METADATA" >/dev/null

  printf 'PASS release API reports uploaded DMG, checksum, and manifest assets\n'
  printf 'PASS metadata mode did not request DMG bytes\n'
  exit 0
fi

DOWNLOADED_DMG="$WORK_DIR/$DMG_FILE"
DOWNLOADED_CHECKSUM="$WORK_DIR/$DMG_FILE.sha256"
DOWNLOADED_MANIFEST="$WORK_DIR/release-manifest.json"

"${CURL[@]}" "$DMG_URL" --output "$DOWNLOADED_DMG"
"${CURL[@]}" "$CHECKSUM_URL" --output "$DOWNLOADED_CHECKSUM"
"${CURL[@]}" "$MANIFEST_URL" --output "$DOWNLOADED_MANIFEST"

EXPECTED_SHA256="$(awk 'NR == 1 { print tolower($1) }' "$DOWNLOADED_CHECKSUM")"
CHECKSUM_FILE_NAME="$(awk 'NR == 1 { print $2 }' "$DOWNLOADED_CHECKSUM")"
CHECKSUM_FILE_NAME="${CHECKSUM_FILE_NAME#\*}"
if [[ ! "$EXPECTED_SHA256" =~ ^[0-9a-f]{64}$ || "$CHECKSUM_FILE_NAME" != "$DMG_FILE" ]]; then
  echo "The published checksum file is malformed or names a different artifact." >&2
  exit 1
fi

if command -v shasum >/dev/null 2>&1; then
  ACTUAL_SHA256="$(shasum -a 256 "$DOWNLOADED_DMG" | awk '{print tolower($1)}')"
elif command -v sha256sum >/dev/null 2>&1; then
  ACTUAL_SHA256="$(sha256sum "$DOWNLOADED_DMG" | awk '{print tolower($1)}')"
else
  echo "beta_site_health.sh requires shasum or sha256sum." >&2
  exit 2
fi

if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
  echo "Downloaded DMG bytes do not match the published checksum." >&2
  exit 1
fi

jq --exit-status \
  --arg releaseLabel "${TAG#v}" \
  --arg dmgFile "$DMG_FILE" \
  --arg dmgSHA256 "$ACTUAL_SHA256" \
  --arg uuidPattern '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' \
  '
    .schemaVersion == 1 and
    .product == "eaSplit" and
    .releaseLabel == $releaseLabel and
    .dmgFile == $dmgFile and
    (.dmgSHA256 | ascii_downcase) == $dmgSHA256 and
    (.sourceCommit | test("^[0-9a-f]{40}$")) and
    (.appNotarizationId | test($uuidPattern)) and
    (.dmgNotarizationId | test($uuidPattern))
  ' "$DOWNLOADED_MANIFEST" >/dev/null

printf 'PASS downloaded DMG SHA-256 %s\n' "$ACTUAL_SHA256"
printf 'PASS release manifest matches %s and records notarization IDs\n' "$TAG"
