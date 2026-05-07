#!/usr/bin/env bash
# End-to-end test for the setup skill, driven by the Codex CLI.
#
# Mirrors test/run.sh but uses `codex exec` instead of `claude -p`. The
# skill format is identical for both agents (same SKILL.md frontmatter,
# same body); the only differences are how the agent is launched and
# how the skill is made available to it.
#
# Codex picks up skills from $CODEX_HOME/skills, so the harness sets
# $CODEX_HOME to a sandboxed scratch directory and copies this repo's
# skills/setup tree under it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKETPLACE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PORT="${CODER_TEST_PORT:-17081}"
ACCESS_URL="http://127.0.0.1:${PORT}"
EMAIL="test@example.com"
USERNAME="admin"
FULL_NAME="Test Admin"
PASSWORD="TestPassword123!"
TEMPLATE_NAME="docker"
WORKSPACE_NAME="demo"
TIMEOUT_SECONDS="${CODER_TEST_TIMEOUT:-1500}"

WORKDIR="$(mktemp -d -t coder-setup-codex-e2e.XXXXXX)"
TESTDIR="$WORKDIR/coder-test"
FAKE_HOME="$WORKDIR/home"
FAKE_CODEX_HOME="$WORKDIR/codex-home"
mkdir -p "$TESTDIR" "$FAKE_HOME/.config" "$FAKE_CODEX_HOME/skills"
cd "$TESTDIR"

cleanup() {
  if [ -f "$TESTDIR/docker-compose.yml" ]; then
    ( cd "$TESTDIR" && docker compose down -v --remove-orphans >/dev/null 2>&1 || true )
  fi
  docker rm -f "coder-${USERNAME}-${WORKSPACE_NAME}" >/dev/null 2>&1 || true
  rm -rf "$WORKDIR"
}
if [ -z "${CODER_TEST_KEEP:-}" ]; then
  trap cleanup EXIT
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "FAIL: codex CLI not on PATH" >&2
  exit 2
fi
if ! docker version >/dev/null 2>&1; then
  echo "FAIL: docker daemon unreachable" >&2
  exit 2
fi

# Codex needs auth + a model provider config. Inherit whatever the
# host has under ~/.codex (config.toml, auth.json, OS keyring is
# untouched) into the sandbox. The skill itself goes under
# $CODEX_HOME/skills/setup so Codex auto-discovers it.
HOST_CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
if [ -f "$HOST_CODEX_HOME/config.toml" ]; then
  cp "$HOST_CODEX_HOME/config.toml" "$FAKE_CODEX_HOME/config.toml"
fi
if [ -f "$HOST_CODEX_HOME/auth.json" ]; then
  cp "$HOST_CODEX_HOME/auth.json" "$FAKE_CODEX_HOME/auth.json"
fi
# Carry forward Codex's bundled system skills so we don't accidentally
# disable them by overriding CODEX_HOME.
if [ -d "$HOST_CODEX_HOME/skills/.system" ]; then
  cp -r "$HOST_CODEX_HOME/skills/.system" "$FAKE_CODEX_HOME/skills/.system"
fi
cp -r "$MARKETPLACE_DIR/skills/setup" "$FAKE_CODEX_HOME/skills/setup"

PROMPT_FILE="$WORKDIR/prompt.txt"
cat > "$PROMPT_FILE" <<EOF
You are testing the setup skill end-to-end. You MUST use the
setup skill in \$CODEX_HOME/skills/setup. Follow every phase. Do
not deviate.

Constraints:

- DO NOT run a host install. Use Docker compose.
- DO NOT pkill coder. Ever.
- DO NOT use the auto-tunnel. This test runs in a sandbox with no
  human and no browser; the auto-tunnel access URL is unreachable
  to the verifier. Bind the Coder server on $ACCESS_URL exactly,
  with the container listening on 0.0.0.0:7080 and the host port
  mapped to ${PORT}.
- DO NOT use the GitHub first-user auth path. There is no human to
  click "Continue with GitHub". Use the username/password path with
  the credentials below and pass --first-user-trial=false.
- Work entirely under $TESTDIR.

Setup parameters:

- Access URL:    $ACCESS_URL
- Admin email:   $EMAIL
- Admin user:    $USERNAME
- Admin name:    $FULL_NAME
- Admin password: $PASSWORD
- Pass --first-user-trial=false (no enterprise trial license).
- First-user auth: username/password (NOT GitHub)
- Starter template: $TEMPLATE_NAME
- Create one workspace named "$WORKSPACE_NAME" from the $TEMPLATE_NAME template.

When you finish, print a final block titled "RESULT:" with one of
SUCCESS, PARTIAL, or FAILURE and a one-line reason.
EOF

echo "==> running codex exec (this may take several minutes)" >&2
echo "==> testdir:        $TESTDIR" >&2
echo "==> sandboxed HOME: $FAKE_HOME" >&2
echo "==> CODEX_HOME:     $FAKE_CODEX_HOME" >&2

CODEX_OUT="$WORKDIR/codex-output.txt"
set +e
HOME="$FAKE_HOME" XDG_CONFIG_HOME="$FAKE_HOME/.config" CODEX_HOME="$FAKE_CODEX_HOME" \
  timeout "$TIMEOUT_SECONDS" codex exec \
    --skip-git-repo-check \
    --dangerously-bypass-approvals-and-sandbox \
    --cd "$TESTDIR" \
    "$(cat "$PROMPT_FILE")" \
    > "$CODEX_OUT" 2>&1
CODEX_RC=$?
set -e

if [ "$CODEX_RC" -ne 0 ]; then
  echo "FAIL: codex exited with $CODEX_RC" >&2
  echo "---- codex output (last 80 lines) ----" >&2
  tail -n 80 "$CODEX_OUT" >&2 || true
  exit 1
fi

echo "==> verifying via REST API" >&2

fail() {
  echo "FAIL: $*" >&2
  echo "---- codex output (last 60 lines) ----" >&2
  tail -n 60 "$CODEX_OUT" >&2 || true
  exit 1
}

# 1) /healthz
curl -fsS "$ACCESS_URL/healthz" >/dev/null || fail "GET /healthz did not return 200"

# 2) Authenticate via the API.
LOGIN_JSON="$(curl -fsS -X POST \
  -H 'content-type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" \
  "$ACCESS_URL/api/v2/users/login")" \
  || fail "login API failed (skill did not bootstrap the admin user)"
SESSION="$(echo "$LOGIN_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["session_token"])')"
[ -n "$SESSION" ] || fail "empty session token from login API"

# 3) users
USERS_JSON="$(curl -fsS -H "Coder-Session-Token: $SESSION" "$ACCESS_URL/api/v2/users")" \
  || fail "GET /api/v2/users failed"
echo "$USERS_JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['count'] == 1, f'expected 1 user, got {d[\"count\"]}'
u = d['users'][0]
assert u['username'] == '$USERNAME', u
assert u['email'] == '$EMAIL', u
assert any(r['name'] == 'owner' for r in u['roles']), u
print('ok: user', u['username'])
" || fail "users verification failed"

# 4) docker template
TEMPLATES_JSON="$(curl -fsS -H "Coder-Session-Token: $SESSION" "$ACCESS_URL/api/v2/organizations/default/templates")" \
  || fail "GET templates failed"
echo "$TEMPLATES_JSON" | python3 -c "
import json, sys
templates = json.load(sys.stdin)
names = [t['name'] for t in templates]
assert '$TEMPLATE_NAME' in names, f'templates: {names}'
print('ok: template', '$TEMPLATE_NAME')
" || fail "templates verification failed"

# 5) demo workspace.
WS_DEADLINE=$(( $(date +%s) + 300 ))
while :; do
  WS_JSON="$(curl -fsS -H "Coder-Session-Token: $SESSION" "$ACCESS_URL/api/v2/workspaces")" \
    || fail "GET /api/v2/workspaces failed"
  WS_STATE="$(printf '%s' "$WS_JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
ws = [w for w in d.get('workspaces', []) if w['name'] == '$WORKSPACE_NAME']
if not ws:
    print('missing'); raise SystemExit(0)
b = ws[0]['latest_build']
lifecycles = []
for r in (b.get('resources') or []):
    for a in (r.get('agents') or []):
        lifecycles.append(a.get('lifecycle_state', 'unknown'))
lc = lifecycles[0] if lifecycles else 'no-agent'
print(f\"{b['job']['status']},{b['status']},{b['transition']},{lc}\")
")"
  case "$WS_STATE" in
    succeeded,running,start,ready)
      echo "ok: workspace $WORKSPACE_NAME job=succeeded status=running transition=start agent=ready"
      break
      ;;
    failed,*|canceled,*|*,failed,*|*,canceled,*|*,*,*,start_error|*,*,*,start_timeout)
      fail "workspace failed: $WS_STATE"
      ;;
    missing)
      fail "no workspace named $WORKSPACE_NAME"
      ;;
  esac
  if [ "$(date +%s)" -gt "$WS_DEADLINE" ]; then
    fail "workspace did not reach succeeded,running,start,ready within 5 minutes (last=$WS_STATE)"
  fi
  sleep 5
done

echo "PASS"
