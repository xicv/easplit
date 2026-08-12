#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/eaSplit.xcodeproj"
BUILD_ROOT="$ROOT_DIR/.build/quality"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
RESULT_BUNDLE="$BUILD_ROOT/eaSplitTests.xcresult"
PROJECT_SNAPSHOT="$(/usr/bin/mktemp -t easplit-project)"
trap '/bin/rm -f "$PROJECT_SNAPSHOT"' EXIT

for command in git swiftlint xcodebuild xcodegen; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command is unavailable: $command" >&2
    exit 1
  fi
done

cd "$ROOT_DIR"
git diff --check
"$ROOT_DIR/script/lint_changed.sh"

/bin/cp "$PROJECT_PATH/project.pbxproj" "$PROJECT_SNAPSHOT"
xcodegen generate --spec "$ROOT_DIR/project.yml" --project "$ROOT_DIR"
if ! /usr/bin/cmp -s "$PROJECT_SNAPSHOT" "$PROJECT_PATH/project.pbxproj"; then
  echo "Generated Xcode project was stale. Review and commit the regenerated project." >&2
  exit 1
fi

if [[ -e "$RESULT_BUNDLE" ]]; then
  /bin/rm -rf "$RESULT_BUNDLE"
fi

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme eaSplit \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -enableCodeCoverage YES \
  -resultBundlePath "$RESULT_BUNDLE" \
  CODE_SIGNING_ALLOWED=NO \
  test

/usr/bin/xcrun xccov view --report --json "$RESULT_BUNDLE" >"$BUILD_ROOT/coverage.json"
EASPLIT_COVERAGE_JSON="$BUILD_ROOT/coverage.json" /usr/bin/ruby <<'RUBY'
require "json"

report = JSON.parse(File.read(ENV.fetch("EASPLIT_COVERAGE_JSON")))
target = report.fetch("targets").find { |candidate| candidate.fetch("name") == "eaSplit.app" }
abort("Coverage report does not contain eaSplit.app") unless target

percentage = target.fetch("lineCoverage") * 100
minimum = 20.0
puts format("Production line coverage: %.2f%% (minimum %.2f%%)", percentage, minimum)
abort("Production line coverage is below the minimum") if percentage < minimum

critical_files = {
  "AppModel.swift" => 75.0,
  "LayoutEngine.swift" => 95.0,
  "RecipeStore.swift" => 90.0,
  "WindowFrameTransaction.swift" => 90.0,
}
files = target.fetch("files").to_h { |file| [File.basename(file.fetch("name")), file] }

critical_files.each do |name, file_minimum|
  file = files[name]
  abort("Coverage report does not contain critical module #{name}") unless file

  file_percentage = file.fetch("lineCoverage") * 100
  puts format(
    "%-30s %.2f%% (minimum %.2f%%)",
    name,
    file_percentage,
    file_minimum
  )
  abort("#{name} coverage is below the minimum") if file_percentage < file_minimum
end
RUBY

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme eaSplit \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  analyze

echo "Quality gate passed. Evidence: $BUILD_ROOT"
