#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: $0 /absolute/path/to/developer-id.p12 /absolute/path/to/AuthKey.p8 KEY_ID ISSUER_ID" >&2
  exit 2
fi

P12_PATH="$1"
P8_PATH="$2"
KEY_ID="$3"
ISSUER_ID="$4"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOSITORY="${EASPLIT_GITHUB_REPOSITORY:-xicv/easplit}"
ENVIRONMENT="release-candidate"

for path in "$P12_PATH" "$P8_PATH"; do
  if [[ "$path" != /* || ! -f "$path" ]]; then
    echo "Expected an existing absolute credential path, found: $path" >&2
    exit 2
  fi
  if [[ "$path" == "$ROOT_DIR"/* ]]; then
    echo "Credential files must remain outside the eaSplit repository: $path" >&2
    exit 2
  fi
done

if [[ "$P12_PATH" != *.p12 || "$P8_PATH" != *.p8 ]]; then
  echo "Expected a .p12 Developer ID export and a .p8 App Store Connect key." >&2
  exit 2
fi
if [[ ! "$KEY_ID" =~ ^[A-Za-z0-9]{10,}$ ]]; then
  echo "The App Store Connect key ID is invalid." >&2
  exit 2
fi
if [[ ! "$ISSUER_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
  echo "The App Store Connect issuer ID must be a UUID." >&2
  exit 2
fi
if [[ "${EASPLIT_CONFIRM_SECRET_UPLOAD:-}" != "$ENVIRONMENT" ]]; then
  echo "Set EASPLIT_CONFIRM_SECRET_UPLOAD=$ENVIRONMENT to authorize the encrypted secret upload." >&2
  exit 1
fi

gh auth status >/dev/null
gh api "repos/$REPOSITORY/environments/$ENVIRONMENT" >/dev/null
read -r -s -p "Developer ID P12 password: " P12_PASSWORD
echo
if [[ -z "$P12_PASSWORD" ]]; then
  echo "The Developer ID P12 password cannot be empty." >&2
  exit 1
fi

if ! CERTIFICATE_SUBJECT="$(
  printf '%s\n' "$P12_PASSWORD" \
    | /usr/bin/openssl pkcs12 -in "$P12_PATH" -passin stdin -clcerts -nokeys 2>/dev/null \
    | /usr/bin/openssl x509 -noout -subject 2>/dev/null
)"; then
  echo "The P12 password is invalid or the export does not contain a certificate." >&2
  exit 1
fi
if ! /usr/bin/grep -Fq "Developer ID Application: XI CAO (6UVB8NWW6F)" <<<"$CERTIFICATE_SUBJECT"; then
  echo "The P12 is not the expected eaSplit Developer ID Application identity." >&2
  exit 1
fi
if ! /usr/bin/head -n 1 "$P8_PATH" | /usr/bin/grep -Eq '^-----BEGIN (EC )?PRIVATE KEY-----$'; then
  echo "The App Store Connect .p8 file is not a PEM private key." >&2
  exit 1
fi

/usr/bin/base64 -i "$P12_PATH" \
  | gh secret set EASPLIT_DEVELOPER_ID_P12_BASE64 --env "$ENVIRONMENT" --repo "$REPOSITORY"
printf '%s' "$P12_PASSWORD" \
  | gh secret set EASPLIT_DEVELOPER_ID_P12_PASSWORD --env "$ENVIRONMENT" --repo "$REPOSITORY"
/usr/bin/base64 -i "$P8_PATH" \
  | gh secret set EASPLIT_NOTARY_KEY_P8_BASE64 --env "$ENVIRONMENT" --repo "$REPOSITORY"
printf '%s' "$KEY_ID" \
  | gh secret set EASPLIT_NOTARY_KEY_ID --env "$ENVIRONMENT" --repo "$REPOSITORY"
printf '%s' "$ISSUER_ID" \
  | gh secret set EASPLIT_NOTARY_ISSUER_ID --env "$ENVIRONMENT" --repo "$REPOSITORY"
unset P12_PASSWORD

echo "Configured encrypted release-candidate secrets for $REPOSITORY."
