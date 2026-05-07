# First-user sign-in via GitHub device flow

This is the scripted version of the "Sign in with GitHub" path,
for fresh deployments where the default GitHub OAuth App that
ships with the Coder server is in effect (the server log shows
`injecting default github external auth provider`, or
`/api/v2/users/authmethods` returns
`github.default_provider_configured=true`).

The default provider has GitHub's RFC 8628 device flow turned
on. That means the skill can drive the whole sign-in from the
terminal: it prints a short URL and a one-time code, the user
pastes the code into github.com on whatever device is convenient
(their phone is fine), and the server polls GitHub until they
finish. No browser on the install machine, no `--first-user-*`
flags, no password to record. The first user to complete the
flow becomes the deployment Owner because of the `userCount==0`
rule in `coderd/userauth.go`.

## Critical: the agent must run this in three separate tool
## calls, with the user-facing message between them

This is the most common way the recipe is implemented wrong.

Most agent tool runners buffer a shell command's stdout and only
return it after the process exits. If you put step 2 (fetch the
code) and step 3 (poll until the user enters it) in one shell
command, the `echo` of the user code lands in the buffer, the
poll loop sits for up to 15 minutes, and the user never sees the
URL or the code. From the user's perspective, the chat just
hangs.

Run this as **three** separate tool calls, in order:

1. **Fetch.** Prime the cookie jar, fetch the device code, write
   the values to a state file. Returns in ~3 seconds.
2. **Tell the user.** Read the values from the state file in the
   agent (no shell). Send a chat message to the user with the
   URL and the code. Wait for the user to acknowledge they've
   entered it -- a single "ok" / "done" / "I entered it" is
   enough.
3. **Poll.** Hit the callback in a tight loop until it returns
   200, then write the session token to `$CODER_CONFIG_DIR`.

Do **not** try to combine these. Do **not** put a `cat <<MSG`
or `echo` inside the polling loop. The user only sees what the
agent says in chat, not what shell stdout produces, until the
shell command exits.

## When to use it

Use this path when **all three** of these are true:

- The deployment is fresh (zero users).
- `GET $ACCESS_URL/api/v2/users/authmethods` returns
  `github.default_provider_configured=true`. If false, the
  operator has either disabled the default or registered a
  custom GitHub OAuth App; in the second case the standard
  browser authorization-code flow applies (use
  `coder login $ACCESS_URL` and tell the user to click the
  button), and in the first case fall back to email-and-password.
- `GET $ACCESS_URL/api/v2/users/oauth2/github/device` returns a
  `device_code` and a `verification_uri`. If it returns
  `{"message": "Device flow is not enabled for Github OAuth2."}`,
  the deployment has device flow disabled (this happens for
  custom-configured GitHub providers); fall back.

If any of those is false, do NOT try device flow. Use the
fallbacks above.

## Step 1: Fetch the device code

This script primes the OAuth cookies, fetches the device code
from Coder's API, and writes everything the next steps need to a
state file. It exits in ~3 seconds. **Do not** make it print the
instructions to the user; that comes in step 2 as a chat message.

```sh
set -euo pipefail

ACCESS_URL="${ACCESS_URL:?must be set}"
STATE_DIR="${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/coder-install}"
mkdir -p "$STATE_DIR"
JAR="$STATE_DIR/github-device.jar"
DEV_FILE="$STATE_DIR/github-device.env"

# 1a. Prime: hit the GitHub callback with no params. The server
#     redirects (HTTP 307) to /login/device?state=<random>, and on
#     the way it sets oauth_state, oauth_redirect, and
#     oauth_pkce_verifier cookies. We don't follow the redirect;
#     we just need the cookies and the state value from the
#     Location header.
LOC="$(curl -sS -D - -o /dev/null \
  --cookie-jar "$JAR" --max-redirs 0 \
  "$ACCESS_URL/api/v2/users/oauth2/github/callback" \
  | awk -F': ' 'tolower($1) == "location" { sub(/\r$/,"",$2); print $2 }')"
STATE="${LOC##*state=}"
[ -n "$STATE" ] || { echo "could not parse oauth state from $LOC" >&2; exit 1; }

# 1b. Ask the server for a GitHub device code. The server proxies
#     to GitHub's /login/device/code endpoint and returns the
#     values the user needs.
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
```

The script's stdout looks like:

```text
DEVICE_CODE='abc123...'
USER_CODE='ABCD-1234'
VERIFY_URI='https://github.com/login/device'
INTERVAL=5
EXPIRES_IN=900
STATE='a1b2c3...'
```

## Step 2: Tell the user (agent message, not shell output)

After step 1 returns, the agent sends a chat message to the user
with the URL and the code. **This is a chat message from the
agent, not a `cat`/`echo` in a shell command.** Use whatever
your runner uses for "say this to the user".

The message should be roughly:

```text
To sign in to Coder, open this on any device (your phone is
fine):

  <VERIFY_URI>

Enter this code:

  <USER_CODE>

The code is good for <EXPIRES_IN/60> minutes. When you're done,
say "ok" and I'll finish setting you up as the admin.
```

Wait for the user to acknowledge. A short reply ("ok", "done",
"I entered it") is enough; if they say "different method" or
similar, abandon the flow and use email-and-password instead.

While waiting, you may also poll in the background if the runner
supports it (see step 3). On a runner that doesn't, just wait for
the user to acknowledge before starting step 3. The polling
window is 15 minutes, so the user has plenty of time.

`https://github.com/login/device` is the standard
`verification_uri` GitHub returns for the default provider. Don't
hardcode it; read it out of the device-endpoint response so it
survives upstream changes.

## Step 3: Poll the callback (separate tool call)

After the user acknowledges (or in parallel if the runner
supports background processes), poll Coder's callback until it
returns 200. Run this as its own command so its stdout/stderr
isn't mingled with the user-facing message above.

```sh
set -euo pipefail

ACCESS_URL="${ACCESS_URL:?must be set}"
STATE_DIR="${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/coder-install}"
JAR="$STATE_DIR/github-device.jar"
DEV_FILE="$STATE_DIR/github-device.env"
RESP="$STATE_DIR/github-device.resp"

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
DEADLINE=$(( $(date +%s) + EXPIRES_IN ))
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
        slow_down)             INTERVAL=$((INTERVAL + 5)) ;;
        expired_token|access_denied|*)
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
[ -n "$TOKEN" ] || { echo "no coder_session_token in cookie jar" >&2; exit 1; }

CFG="${CODER_CONFIG_DIR:-$HOME/.config/coderv2}"
mkdir -p "$CFG"
umask 0077
printf '%s' "$ACCESS_URL" > "$CFG/url"
printf '%s' "$TOKEN"      > "$CFG/session"

# Clean up the device-flow scratch files; they're useless after
# the session is captured.
rm -f "$JAR" "$DEV_FILE" "$RESP"

# Verify the CLI is signed in as the admin.
coder whoami
coder users list
```

`users list` should show exactly one row with `OWNER` in the
roles column, with the email and login from the user's GitHub
account.

## Common failures

- **The user never sees the code; the chat just hangs.** The
  recipe was run as a single shell command instead of three
  separate tool calls. Step 1 wrote the code to stdout, but the
  poll loop in step 3 didn't return for 15 minutes, and the
  runner buffered stdout until exit. Split the recipe into three
  tool calls as documented above; send the code via an agent
  chat message, not via `cat`/`echo` in a shell command.
- **`{"message": "Device flow is not enabled for Github OAuth2."}`
  on the device endpoint.** The deployment is using a custom
  GitHub OAuth App without `device_flow=true`. Fall back to
  email-and-password, or to the browser flow if a browser is
  available. Don't try to enable device flow for them; that's a
  template / config decision the operator owns.
- **`{"message": "Github OAuth2 is not enabled."}` on the device
  endpoint.** GitHub login is off entirely. Use email-and-password.
- **`authorization_pending` returned forever.** The user hasn't
  entered the code on github.com yet. This is expected; keep
  polling at the `interval` from the device response. Don't poll
  faster than that; GitHub will return `slow_down` and may
  rate-limit the deployment.
- **`expired_token`.** The 15-minute window passed. Restart from
  step 1.
- **`State must be provided.` or `State mismatched.`** Step 1's
  cookies didn't make it to step 3, or step 3 used a different
  `state` than step 1's Location header. Both steps must use the
  same `$STATE_DIR/github-device.jar` (cookies) and
  `$STATE_DIR/github-device.env` (state value).
- **`PKCE challenge must be provided.`** The cookie jar doesn't
  contain `oauth_pkce_verifier`. The GitHub provider is
  configured with PKCE S256 always (see
  `coderd/userauth.go:GithubOAuth2Config.PKCESupported`); the
  prime step must use `--cookie-jar` so curl picks up the cookie.
- **No `coder_session_token` in the jar after a 200.** Something
  changed in the server's session-cookie naming. Check the
  `Set-Cookie` headers of the 200 response directly; if a
  prefixed cookie name is used (`__Host-coder_session_token`),
  the value is still the session token. The CLI accepts either
  when written to `$CODER_CONFIG_DIR/session`.

## Why device flow over the browser flow?

- The install machine often has no browser (servers, CI,
  containers, headless VMs). Device flow works regardless.
- The browser flow needs `coder login`, which writes to the
  default config dir and clobbers the user's existing session if
  they're already signed in to a different deployment.
- The user usually has a phone within reach. Punching in a short
  code is faster than tab-switching and approving an OAuth
  dialog on a desktop.

The browser flow is still appropriate when a custom GitHub OAuth
App without device flow is in effect; in that case there's no
device endpoint to drive.
