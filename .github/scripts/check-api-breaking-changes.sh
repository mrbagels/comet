#!/usr/bin/env bash

set -euo pipefail

base_tag="${1:-$(git describe --tags --abbrev=0 2>/dev/null || true)}"
output_file="${API_DIFF_OUTPUT:-${TMPDIR:-/tmp}/comet-api-diff.txt}"
clean_after_api_diff=0

if [[ -z "$base_tag" ]]; then
  echo "No release tag found; skipping API diff."
  exit 0
fi

run_api_diff() {
  set +e
  swift package diagnose-api-breaking-changes "$base_tag" > "$output_file" 2>&1
  status=$?
  set -e
}

run_api_diff

if [[ "$status" -ne 0 ]] && grep -q "SwiftSyntax.SyntaxRewriter" "$output_file"; then
  echo "SwiftSyntax macro linker state is stale; cleaning SwiftPM build artifacts and retrying." > "$output_file.retry"
  swift package clean >> "$output_file.retry" 2>&1
  clean_after_api_diff=1
  run_api_diff
  cat "$output_file.retry" "$output_file" > "$output_file.combined"
  mv "$output_file.combined" "$output_file"
  rm -f "$output_file.retry"
fi

filtered_output_file="${output_file}.filtered"
awk '
  /^warning: .*found [0-9]+ file\(s\) which are unhandled; explicitly declare them as resources or exclude from the target$/ {
    warning = $0
    if ((getline pathline) > 0) {
      if (pathline ~ /\.docc$/) {
        next
      }
      print warning
      print pathline
      next
    }
    print warning
    next
  }
  { print }
' "$output_file" > "$filtered_output_file"
mv "$filtered_output_file" "$output_file"

cat "$output_file"

{
  echo "### Public API diff"
  echo
  echo "Base tag: \`$base_tag\`"
  echo
  echo '```'
  cat "$output_file"
  echo '```'
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

if [[ "$status" -eq 0 ]]; then
  if [[ "$clean_after_api_diff" -eq 1 ]]; then
    swift package clean > /dev/null 2>&1 || true
  fi
  exit 0
fi

echo "::error::Breaking public API changes detected against $base_tag."

changed_files="$(git diff --name-only "$base_tag"...HEAD || true)"
if ! grep -qx "CHANGELOG.md" <<< "$changed_files"; then
  echo "::error::Breaking API changes must update CHANGELOG.md with release impact."
fi

echo "::error::Intentional public API breaks should wait for a minor release branch and be called out in release notes."
if [[ "$clean_after_api_diff" -eq 1 ]]; then
  swift package clean > /dev/null 2>&1 || true
fi
exit "$status"
