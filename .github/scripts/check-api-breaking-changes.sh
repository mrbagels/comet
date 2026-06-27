#!/usr/bin/env bash

set -euo pipefail

base_tag="${1:-$(git describe --tags --abbrev=0 2>/dev/null || true)}"
output_file="${API_DIFF_OUTPUT:-${TMPDIR:-/tmp}/comet-api-diff.txt}"

if [[ -z "$base_tag" ]]; then
  echo "No release tag found; skipping API diff."
  exit 0
fi

set +e
swift package diagnose-api-breaking-changes "$base_tag" > "$output_file" 2>&1
status=$?
set -e

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
  exit 0
fi

echo "::error::Breaking public API changes detected against $base_tag."

changed_files="$(git diff --name-only "$base_tag"...HEAD || true)"
if ! grep -qx "CHANGELOG.md" <<< "$changed_files"; then
  echo "::error::Breaking API changes must update CHANGELOG.md with release impact."
fi

echo "::error::Intentional public API breaks should wait for a minor release branch and be called out in release notes."
exit "$status"
