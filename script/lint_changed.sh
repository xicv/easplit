#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT_BASE="${EASPLIT_LINT_BASE:-}"
FILE_LIST="$(/usr/bin/mktemp -t easplit-swiftlint)"
trap '/bin/rm -f "$FILE_LIST"' EXIT

cd "$ROOT_DIR"

if [[ -n "$LINT_BASE" ]] && git rev-parse --verify "$LINT_BASE^{commit}" >/dev/null 2>&1; then
  git diff --name-only --diff-filter=ACMR "$LINT_BASE"...HEAD -- '*.swift' >>"$FILE_LIST"
else
  git diff --name-only --diff-filter=ACMR HEAD -- '*.swift' >>"$FILE_LIST"
fi

git ls-files --others --exclude-standard -- '*.swift' >>"$FILE_LIST"
/usr/bin/sort -u -o "$FILE_LIST" "$FILE_LIST"

FILES=()
while IFS= read -r file; do
  [[ -n "$file" && -f "$file" ]] && FILES+=("$file")
done <"$FILE_LIST"

if [[ "${#FILES[@]}" -eq 0 ]]; then
  echo "SwiftLint: no modified or created Swift files."
  exit 0
fi

echo "SwiftLint: checking ${#FILES[@]} modified or created Swift files."
swiftlint lint \
  --strict \
  --quiet \
  --config "$ROOT_DIR/.swiftlint.yml" \
  "${FILES[@]}"
