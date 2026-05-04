#!/usr/bin/env bash
# End-to-end test for the install-coder skill.
#
# Drives `claude -p` with the marketplace in this repo and verifies the
# resulting Coder deployment via the REST API. Designed to be safe to
# run on a Coder workspace: the skill itself refuses a host install in
# that case and falls back to Docker compose.

set -euo pipefail

# Resolve the marketplace root regardless of where the script is called from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKETPLACE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PORT="${CODER_TEST_PORT:-17080}"
ACCESS_URL="http://127.0.0.1:${PORT}"
EMAIL="test@example.com"
USERNAME="admin"
FULL_NAME="Test Admin"
PASSWORD="TestPassword123!"
TEMPLATE_NAME="docker"
WORKSPACE_NAME="demo"
TIMEOUT_SECONDS="${CODER_TEST_TIMEOUT:-1500}"

WORKDIR="$(mktemp -d -t install-coder-e2e.XXXXXX)"
TESTDIR="$WORKDIR/coder-test"
mkdir -p "$TESTDIR"
cd "$TESTDIR"

cleanup() {
  # Tear down only via Docker compose. Never `pkill coder`.
  if [ -f "$TESTDIR/docker-compose.yml" ]; then
    ( cd "$TESTDIR" && docker compose down -v --remove-orphans >/dev/null 2>&1 || true )
  fi
  rm -rf "$WORKDIR"
}
if [ -z "${CODER_TEST_KEEP:-}" ]; then
  trap cleanup EXIT
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "FAIL: claude CLI not on PATH" >&2
  exit 2
fi
if ! docker version >/dev/null 2>&1; then
  echo "FAIL: docker daemon unreachable" >&2
  exit 2
fi

PROMPT_FILE="$WORKDIR/prompt.txt"
cat > "$PROMPT_FILE" <<EOF
You are testing the install-coder skill end-to-end. You MUST use the
install-coder skill. Follow every phase. Do not deviate.

Constraints:

- DO NOT run a host install. Use Docker compose.
- DO NOT pkill coder. Ever.
- Bind the Coder server on $ACCESS_URL.
- Work entirely under $TESTDIR.

Setup parameters:

- Access URL:    $ACCESS_URL
- Admin email:   $EMAIL
- Admin user:    $USERNAME
- Admin name:    $FULL_NAME
- Admin password: $PASSWORD
- Trial:         false
- Starter template: $TEMPLATE_NAME
- Create one workspace named "$WORKSPACE_NAME" from the $TEMPLATE_NAME template.

When you finish, print a final block titled "RESULT:" with one of
SUCCESS, PARTIAL, or FAILURE and a one-line reason.
EOF

echo "==> running claude -p (this may take several minutes)" >&2
echo "==> testdir: $TESTDIR" >&2

CLAUDE_OUT="$WORKDIR/claude-output.txt"
set +e
timeout "$TIMEOUT_SECONDS" claude -p \
  --plugin-dir "$MARKETPLACE_DIR" \
  --permission-mode bypassPermissions \
  --output-format text \
  --add-dir "$TESTDIR" \
  < "$PROMPT_FILE" \
  > "$CLAUDE_OUT" 2>&1
CLAUDE_RC=$?
set -e

if [ "$CLAUDE_RC" -ne 0 ]; then
  echo "FAIL: claude exited with $CLAUDE_RC" >&2
  echo "---- claude output (last 80 lines) ----" >&2
  tail -n 80 "$CLAUDE_OUT" >&2 || true
  exit 1
fi

echo "==> verifying via REST API" >&2

fail() {
  echo "FAIL: $*" >&2
  echo "---- claude output (last 60 lines) ----" >&2
  tail -n 60 "$CLAUDE_OUT" >&2 || true
  exit 1
}

# 1) /healthz
curl -fsS "$ACCESS_URL/healthz" >/dev/null || fail "GET /healthz did not return 200"

# 2) admin user
SESSION_FILE="$TESTDIR/data/session"
[ -s "$SESSION_FILE" ] || fail "session file missing at $SESSION_FILE"
SESSION="$(cat "$SESSION_FILE")"

USERS_JSON="$(curl -fsS -H "Coder-Session-Token: $SESSION" "$ACCESS_URL/api/v2/users")" \
  || fail "GET /api/v2/users failed"
echo "$USERS_JSON" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["count"] == 1, f"expected 1 user, got {d[\"count\"]}"
u = d["users"][0]
assert u["username"] == "'"$USERNAME"'", u
assert u["email"] == "'"$EMAIL"'", u
assert any(r["name"] == "owner" for r in u["roles"]), u
print("ok: user", u["username"])
' || fail "users verification failed"

# 3) docker template
TEMPLATES_JSON="$(curl -fsS -H "Coder-Session-Token: $SESSION" "$ACCESS_URL/api/v2/organizations/default/templates")" \
  || fail "GET templates failed"
echo "$TEMPLATES_JSON" | python3 -c '
import json, sys
templates = json.load(sys.stdin)
names = [t["name"] for t in templates]
assert "'"$TEMPLATE_NAME"'" in names, f"templates: {names}"
print("ok: template", "'"$TEMPLATE_NAME"'")
' || fail "templates verification failed"

# 4) demo workspace
WS_JSON="$(curl -fsS -H "Coder-Session-Token: $SESSION" "$ACCESS_URL/api/v2/workspaces")" \
  || fail "GET workspaces failed"
echo "$WS_JSON" | python3 -c '
import json, sys
d = json.load(sys.stdin)
ws = [w for w in d.get("workspaces", []) if w["name"] == "'"$WORKSPACE_NAME"'"]
assert ws, f"no workspace named '"$WORKSPACE_NAME"' in {[w[\"name\"] for w in d.get(\"workspaces\", [])]}"
w = ws[0]
status = w["latest_build"]["status"]
transition = w["latest_build"]["transition"]
assert status == "succeeded", f"latest build status={status}"
assert transition == "start", f"latest transition={transition}"
print("ok: workspace", w["name"], "status=", status, "transition=", transition)
' || fail "workspace verification failed"

echo "PASS"
EOF