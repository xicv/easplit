#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /absolute/path/to/temporary.keychain-db" >&2
  exit 2
fi

KEYCHAIN_PATH="$1"
PROFILE_NAME="${EASPLIT_NOTARY_PROFILE:-easplit-ci}"
SIGNING_IDENTITY="${EASPLIT_DEVELOPER_ID:-Developer ID Application: XI CAO (6UVB8NWW6F)}"
REQUIRED_SECRETS=(
  EASPLIT_DEVELOPER_ID_P12_BASE64
  EASPLIT_DEVELOPER_ID_P12_PASSWORD
  EASPLIT_NOTARY_KEY_P8_BASE64
  EASPLIT_NOTARY_KEY_ID
  EASPLIT_NOTARY_ISSUER_ID
)
MISSING_SECRETS=()

for name in "${REQUIRED_SECRETS[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    MISSING_SECRETS+=("$name")
  fi
done

if (( ${#MISSING_SECRETS[@]} > 0 )); then
  echo "Release credentials are incomplete. Missing GitHub environment secrets:" >&2
  printf '  - %s\n' "${MISSING_SECRETS[@]}" >&2
  exit 1
fi

if [[ "${GITHUB_ACTIONS:-}" != "true" || -z "${RUNNER_TEMP:-}" ]]; then
  echo "CI release credentials may only be prepared inside GitHub Actions." >&2
  exit 1
fi

if [[ "$KEYCHAIN_PATH" != "$RUNNER_TEMP"/* || "$KEYCHAIN_PATH" != *.keychain-db ]]; then
  echo "The temporary keychain must be an absolute .keychain-db path inside RUNNER_TEMP." >&2
  exit 2
fi

if [[ -e "$KEYCHAIN_PATH" || -L "$KEYCHAIN_PATH" ]]; then
  echo "Refusing to replace an existing keychain: $KEYCHAIN_PATH" >&2
  exit 1
fi

P12_PATH="$RUNNER_TEMP/easplit-developer-id.p12"
P8_PATH="$RUNNER_TEMP/easplit-notary-key.p8"
KEYCHAIN_PASSWORD="$(/usr/bin/openssl rand -hex 32)"

for path in "$P12_PATH" "$P8_PATH"; do
  if [[ -e "$path" || -L "$path" ]]; then
    echo "Refusing to replace an existing credential file: $path" >&2
    exit 1
  fi
done

cleanup_files() {
  /bin/rm -f "$P12_PATH" "$P8_PATH"
}
trap cleanup_files EXIT
umask 077
set -o noclobber

if ! printf '%s' "$EASPLIT_DEVELOPER_ID_P12_BASE64" | /usr/bin/base64 -D >"$P12_PATH"; then
  echo "Unable to decode EASPLIT_DEVELOPER_ID_P12_BASE64." >&2
  exit 1
fi
if ! printf '%s' "$EASPLIT_NOTARY_KEY_P8_BASE64" | /usr/bin/base64 -D >"$P8_PATH"; then
  echo "Unable to decode EASPLIT_NOTARY_KEY_P8_BASE64." >&2
  exit 1
fi
set +o noclobber

/usr/bin/security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
/usr/bin/security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
/usr/bin/security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
/usr/bin/security import "$P12_PATH" \
  -k "$KEYCHAIN_PATH" \
  -f pkcs12 \
  -P "$EASPLIT_DEVELOPER_ID_P12_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security
/usr/bin/security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "$KEYCHAIN_PASSWORD" \
  "$KEYCHAIN_PATH" >/dev/null
/usr/bin/security list-keychains -d user -s "$KEYCHAIN_PATH"
/usr/bin/security default-keychain -d user -s "$KEYCHAIN_PATH"

AVAILABLE_IDENTITIES="$(/usr/bin/security find-identity -v -p codesigning "$KEYCHAIN_PATH")"
if ! /usr/bin/grep -Fq "\"$SIGNING_IDENTITY\"" <<<"$AVAILABLE_IDENTITIES"; then
  echo "The imported P12 does not contain the required identity: $SIGNING_IDENTITY" >&2
  exit 1
fi

/usr/bin/xcrun notarytool store-credentials "$PROFILE_NAME" \
  --key "$P8_PATH" \
  --key-id "$EASPLIT_NOTARY_KEY_ID" \
  --issuer "$EASPLIT_NOTARY_ISSUER_ID" \
  --keychain "$KEYCHAIN_PATH" \
  --validate

echo "Prepared isolated Developer ID and notarization credentials for this runner."
