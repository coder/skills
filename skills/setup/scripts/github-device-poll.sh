#!/usr/bin/env bash
# Step 3 of the first-user GitHub device-code sign-in.
#
# Polls Coder's GitHub callback until the user has entered the
# device code on github.com, captures the resulting session
# cookie, writes it into $CODER_CONFIG_DIR (or its default), and
# verifies the CLI is signed in. Always cleans up the scratch
# files written by github-device-fetch.sh on exit, success or
# failure.
#
# Run this only after github-device-fetch.sh has succeeded and
# after you have shown the user the URL and code from
# $STATE_DIR/github-device.env. Do not combine the two scripts
# into one shell command; tool runners buffer stdout and the
# user will not see the code until the poll loop returns.
#
# Inputs:
#   ACCESS_URL        required. Same value passed to fetch.
#   STATE_DIR         optional. Same value passed to fetch.
#   CODER_CONFIG_DIR  optional. Where to write url + session.
#                     Default $HOME/.config/coderv2.

set -euo pipefail

ACCESS_URL="${ACCESS_URL:?must be set}"
STATE_DIR="${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/coder-install}"
JAR="$STATE_DIR/github-device.jar"
DEV_FILE="$STATE_DIR/github-device.env"
RESP="$STATE_DIR/github-device.resp"

# Always remove the cookie jar, device env file, and response
# scratch on exit, success or failure. Once the session token is
# captured these are useless and they contain OAuth state that
# shouldn't linger on disk.
cleanup_scratch() { rm -f "$JAR" "$DEV_FILE" "$RESP"; }
trap cleanup_scratch EXIT

# Load DEVICE_CODE, STATE, INTERVAL, EXPIRES_IN.
# shellcheck disable=SC1090
. "$DEV_FILE"

# Poll the callback. The middleware checks the cookie state
# matches the query state and feeds the device_code through the
# server's GithubOAuth2Config.Exchange override, which hits
# GitHub's token endpoint. While the user hasn't entered the
# code, the server returns 400 with detail
# "authorization_pending"; once they have, it returns 200 with
# {"redirect_url": "..."} and a Set-Cookie:
# coder_session_token=... header that's the admin's session.
DEADLINE=$(($(date +%s) + EXPIRES_IN))
while :; do
  HTTP=$(curl -sS -o "$RESP" -w '%{http_code}' \
    --cookie "$JAR" --cookie-jar "$JAR" \
    "$ACCESS_URL/api/v2/users/oauth2/github/callback?code=$DEVICE_CODE&state=$STATE")
  case "$HTTP" in
    200) break ;;
    400)
      DETAIL="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("detail",""))' "$RESP" 2>/dev/null || true)"
      case "$DETAIL" in
        authorization_pending) ;;
        slow_down) INTERVAL=$((INTERVAL + 5)) ;;
        expired_token | access_denied | *)
          echo "github device login failed: $DETAIL" >&2
          cat "$RESP" >&2
          exit 1
          ;;
      esac
      ;;
    *)
      echo "github device login: unexpected HTTP $HTTP" >&2
      cat "$RESP" >&2
      exit 1
      ;;
  esac
  if [ "$(date +%s)" -gt "$DEADLINE" ]; then
    echo "github device login: code expired before user entered it" >&2
    exit 1
  fi
  sleep "$INTERVAL"
done

# Pull the session token out of the cookie jar and write it to
# the directory the coder CLI reads. Two files: url and session,
# both plain text, mode 0600. CODER_CONFIG_DIR overrides the
# default ~/.config/coderv2.
TOKEN="$(awk '$6 == "coder_session_token" { print $7 }' "$JAR" | tail -1)"
[ -n "$TOKEN" ] || {
  echo "no coder_session_token in cookie jar" >&2
  exit 1
}

CFG="${CODER_CONFIG_DIR:-$HOME/.config/coderv2}"
mkdir -p "$CFG"
umask 0077
printf '%s' "$ACCESS_URL" >"$CFG/url"
printf '%s' "$TOKEN" >"$CFG/session"

# Verify the CLI is signed in as the admin. (Scratch files are
# removed by the EXIT trap above.)
coder whoami
coder users list
