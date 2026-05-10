#!/usr/bin/env bash
# Run every linter against the repo. Prints a summary at the end and exits
# non-zero if any check failed. Wired up by `make lint` and the
# `.github/workflows/lint.yml` workflow.
#
# Each check is independent: one tool's failure does not short-circuit the
# rest, so a single CI run reports every problem.

set -uo pipefail

cd "$(dirname "$0")/.."

RC=0
fail() {
  RC=1
  printf '\033[31mFAIL\033[0m %s\n' "$1" >&2
}
ok() {
  printf '\033[32mOK\033[0m   %s\n' "$1"
}

# 1. shellcheck: every *.sh under the repo. Uses .shellcheckrc for global
#    suppressions.
echo "==> shellcheck"
SH_FILES="$(git ls-files '*.sh' 2> /dev/null || find . -name '*.sh' -not -path './.git/*')"
if [ -n "$SH_FILES" ]; then
  if printf '%s\n' "$SH_FILES" | xargs shellcheck; then
    ok "shellcheck"
  else
    fail "shellcheck"
  fi
else
  ok "shellcheck (no files)"
fi

# 2. shfmt --diff: complain if any *.sh would be reformatted. Run with the
#    same flags as `make fmt`.
echo "==> shfmt"
if [ -n "$SH_FILES" ]; then
  if printf '%s\n' "$SH_FILES" | xargs shfmt -d -i 2 -ci > /dev/null; then
    ok "shfmt"
  else
    printf '%s\n' "$SH_FILES" | xargs shfmt -d -i 2 -ci || true
    fail "shfmt (run \`make fmt\` to auto-fix)"
  fi
else
  ok "shfmt (no files)"
fi

# 3. markdownlint-cli2: lints every *.md against .markdownlint-cli2.jsonc.
echo "==> markdownlint"
if npx --yes markdownlint-cli2 > /dev/null 2>&1; then
  ok "markdownlint"
else
  npx --yes markdownlint-cli2 || true
  fail "markdownlint"
fi

# 4. JSON validity: parse every JSON file under .claude-plugin/ and the
#    root. `jq` is strict about trailing commas and BOMs.
echo "==> jq (JSON syntax)"
JSON_FILES="$(git ls-files '*.json' 2> /dev/null | grep -v '^node_modules/' || true)"
if [ -n "$JSON_FILES" ]; then
  JSON_OK=1
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if ! jq -e . "$f" > /dev/null 2>&1; then
      echo "invalid JSON: $f" >&2
      JSON_OK=0
    fi
  done <<< "$JSON_FILES"
  if [ "$JSON_OK" = 1 ]; then
    ok "jq"
  else
    fail "jq"
  fi
else
  ok "jq (no files)"
fi

# 5. Marketplace manifest: validates the Claude Code plugin marketplace.
echo "==> claude plugin validate"
if command -v claude > /dev/null 2>&1; then
  if claude plugin validate . > /tmp/plugin-validate.log 2>&1; then
    ok "claude plugin validate"
  else
    cat /tmp/plugin-validate.log >&2
    fail "claude plugin validate"
  fi
else
  echo "skip: claude CLI not on PATH"
fi

# 6. No emdash / endash / ` -- ` in source. Per the project style guide.
echo "==> emdash / endash"
PATTERNS="$(printf '\xe2\x80\x94|\xe2\x80\x93')" # U+2014, U+2013 in UTF-8.
if git ls-files | grep -v -E '^(node_modules/|\.git/|\.agents/|\.claude/|\.codex/|\.mux/)' \
  | xargs grep -l -P "$PATTERNS" 2> /dev/null; then
  fail "emdash/endash found (use commas, semicolons, or periods instead)"
else
  ok "emdash/endash"
fi

# 7. SKILL.md frontmatter description fits Codex's 1024-char cap. Codex
#    silently drops skills whose frontmatter description, after parsing,
#    exceeds 1024 bytes. Discovered the hard way.
echo "==> SKILL.md description length"
DESC_OK=1
while IFS= read -r f; do
  [ -n "$f" ] || continue
  LEN="$(python3 - "$f" << 'PY'
import re, sys, yaml, pathlib
text = pathlib.Path(sys.argv[1]).read_text()
m = re.match(r'^---\n(.*?)\n---\n', text, re.S)
if not m:
    print(0)
    sys.exit(0)
fm = yaml.safe_load(m.group(1)) or {}
print(len(fm.get('description', '')))
PY
)"
  if [ "$LEN" -gt 1024 ]; then
    echo "$f: description is $LEN chars (max 1024 for Codex)" >&2
    DESC_OK=0
  fi
done <<< "$(git ls-files 'skills/*/SKILL.md')"
if [ "$DESC_OK" = 1 ]; then
  ok "SKILL.md description length"
else
  fail "SKILL.md description length"
fi

echo
if [ "$RC" -eq 0 ]; then
  printf '\033[32mall checks passed\033[0m\n'
else
  printf '\033[31mone or more checks failed\033[0m\n' >&2
fi
exit "$RC"
