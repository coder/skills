#!/usr/bin/env bash
# Step 1 of the first-user GitHub device-code sign-in.
#
# Primes the OAuth cookies, fetches a GitHub device code from the
# Coder server, and writes everything step 3 (poll) needs to a
# state file. Returns in ~3 seconds. Do not run this and the
# polling step in the same shell command; see
# references/first-user-github-device.md for why.
#
# Inputs:
#   ACCESS_URL  required. Base URL of the Coder server.
#   STATE_DIR   optional. Directory for scratch files. Default
#               ${XDG_STATE_HOME:-$HOME/.local/state}/coder-install.
#
# Outputs:
#   $STATE_DIR/github-device.jar  cookie jar with oauth_state /
#                                 oauth_redirect / oauth_pkce_verifier.
#   $STATE_DIR/github-device.env  shell-source file with
#                                 DEVICE_CODE / USER_CODE /
#                                 VERIFY_URI / INTERVAL /
#                                 EXPIRES_IN / STATE.
#   stdout: the contents of github-device.env so the caller can
#           parse it without re-reading the file.

set -euo pipefail

ACCESS_URL="${ACCESS_URL:?must be set}"
STATE_DIR="${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/coder-install}"
mkdir -p "$STATE_DIR"
JAR="$STATE_DIR/github-device.jar"
DEV_FILE="$STATE_DIR/github-device.env"

# Clean up scratch files on any failure. The trap is cleared at
# the bottom so a successful run leaves the files in place for
# step 3; step 3 has its own trap that always removes them.
cleanup_on_failure() { rm -f "$JAR" "$DEV_FILE"; }
trap cleanup_on_failure EXIT

# 1a. Prime: hit the GitHub callback with no params. The server
#     redirects (HTTP 307) to /login/device?state=<random>, and
#     on the way it sets oauth_state, oauth_redirect, and
#     oauth_pkce_verifier cookies. We don't follow the redirect;
#     we just need the cookies and the state value from the
#     Location header.
LOC="$(curl -sS -D - -o /dev/null \
  --cookie-jar "$JAR" --max-redirs 0 \
  "$ACCESS_URL/api/v2/users/oauth2/github/callback" \
  | awk -F': ' 'tolower($1) == "location" { sub(/\r$/,"",$2); print $2 }')"
STATE="${LOC##*state=}"
[ -n "$STATE" ] || { echo "could not parse oauth state from $LOC" >&2; exit 1; }

# 1b. Ask the server for a GitHub device code. The server
#     proxies to GitHub's /login/device/code endpoint and returns
#     the values the user needs.
DEV_JSON="$(curl -sSf "$ACCESS_URL/api/v2/users/oauth2/github/device")"

# 1c. Write the values to a state file the agent and step 3 will
#     read. Plain shell-source format so the polling step can
#     `. "$STATE_DIR/github-device.env"`.
python3 - "$DEV_JSON" "$STATE" <<'PY' > "$DEV_FILE"
import json, sys, shlex
d = json.loads(sys.argv[1])
state = sys.argv[2]
print(f"DEVICE_CODE={shlex.quote(d['device_code'])}")
print(f"USER_CODE={shlex.quote(d['user_code'])}")
print(f"VERIFY_URI={shlex.quote(d['verification_uri'])}")
print(f"INTERVAL={int(d.get('interval', 5))}")
print(f"EXPIRES_IN={int(d.get('expires_in', 900))}")
print(f"STATE={shlex.quote(state)}")
PY
chmod 0600 "$DEV_FILE"

# 1d. Print the values once so the calling agent can read them
#     out of stdout as well as the file. This script returns
#     here; do NOT poll in the same command.
cat "$DEV_FILE"

# Step 1 succeeded. Disarm the failure trap so the files survive
# for step 3 to read.
trap - EXIT
