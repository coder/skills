#!/usr/bin/env bash
# Apply auto-fixers in-place. Wired up by `make fmt`. The lint script
# (`scripts/lint.sh`, `make lint`) is the read-only counterpart and runs
# in CI.

set -euo pipefail

cd "$(dirname "$0")/.."

# 1. shfmt: format every *.sh in place. Same flags `make lint` checks.
SH_FILES="$(git ls-files '*.sh' 2> /dev/null || find . -name '*.sh' -not -path './.git/*')"
if [ -n "$SH_FILES" ]; then
  echo "==> shfmt -w"
  printf '%s\n' "$SH_FILES" | xargs shfmt -w -i 2 -ci
fi

# 2. markdownlint-cli2 --fix: applies the auto-fixable subset (mostly
#    whitespace and list-marker style).
echo "==> markdownlint --fix"
npx --yes markdownlint-cli2 --fix > /dev/null 2>&1 || true

# 3. jq: pretty-print every JSON file with two-space indent. Skips files
#    listed under .claude-plugin/marketplace.json that are intentionally
#    multi-line, since jq preserves that.
echo "==> jq (JSON pretty-print)"
JSON_FILES="$(git ls-files '*.json' 2> /dev/null | grep -v '^node_modules/' || true)"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  TMP="$(mktemp)"
  if jq --indent 2 . "$f" > "$TMP" 2> /dev/null; then
    mv "$TMP" "$f"
  else
    rm -f "$TMP"
    echo "skip: $f (invalid JSON, run \`make lint\` for details)" >&2
  fi
done <<< "$JSON_FILES"

echo "done"
