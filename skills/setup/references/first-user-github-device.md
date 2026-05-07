# First-user sign-in via GitHub device flow

This is the scripted version of the "Sign in with GitHub" path, for
fresh deployments where the default GitHub OAuth App that ships with
the Coder server is in effect (the server log shows `injecting
default github external auth provider`, or
`/api/v2/users/authmethods` returns
`github.default_provider_configured=true`).

The default provider has GitHub's RFC 8628 device flow turned on.
That means we can drive the whole sign-in from the terminal: the
skill prints a short URL and a one-time code, the user pastes the
code into github.com on whatever device is most convenient (their
phone is fine), and the server polls GitHub until they finish. No
browser on the install machine, no `--first-user-*` flags, no
password to record. The first user to complete this flow becomes
the deployment Owner because of the `userCount==0` rule in
`coderd/userauth.go`.

## When to use it

Use this path when **all three** of these are true:

- The deployment is fresh (zero users).
- `GET $ACCESS_URL/api/v2/users/authmethods` returns
  `github.default_provider_configured=true`. If it returns false,
  the operator has either disabled the default or registered a
  custom GitHub OAuth App; in the second case the standard browser
  authorization-code flow applies (use `coder login $ACCESS_URL`
  and tell the user to click the button), and in the first case
  fall back to email-and-password.
- `GET $ACCESS_URL/api/v2/users/oauth2/github/device` returns a
  `device_code` and a `verification_uri`. If it returns
  `{"message": "Device flow is not enabled for Github OAuth2."}`,
  the deployment has device flow disabled (this happens for
  custom-configured GitHub providers); fall back.

If any of those is false, do NOT try device flow. Use the
fallbacks above.

## What the user sees

Print exactly this when you're ready (substitute the values from
the API response):

```text
To sign in to Coder, open this on any device:

  https://github.com/login/device

Then enter this code:

  ABCD-1234

I'll wait here. As soon as GitHub confirms it, I'll finish setting
you up as the admin. (The code is good for 15 minutes; tell me if
you'd rather pick a different sign-in method.)
```

`https://github.com/login/device` is the standard `verification_uri`
GitHub returns for the default provider. Don't hardcode it; read
it out of the device-endpoint response so it survives upstream
changes.

## The recipe

Three HTTP calls. The first primes the cookies the callback
middleware needs. The second fetches the device code. The third
polls until the user enters the code on GitHub.

```sh
set -euo pipefail

ACCESS_URL="${ACCESS_URL:?must be set}"
JAR="$(mktemp)"
trap 'rm -f "$JAR"' EXIT

# 1. Prime: hit the GitHub callback with no params. The server
#    redirects (HTTP 307) to /login/device?state=<random>, and on
#    the way it sets oauth_state, oauth_redirect, and
#    oauth_pkce_verifier cookies. We don't follow the redirect; we
#    just need the cookies and the state value from the Location
#    header.
LOC="$(curl -sS -D - -o /dev/null \
  --cookie-jar "$JAR" --max-redirs 0 \
  "$ACCESS_URL/api/v2/users/oauth2/github/callback" \
  | awk -F': ' 'tolower($1) == "location" { sub(/\r$/,"",$2); print $2 }')"
STATE="${LOC##*state=}"
[ -n "$STATE" ] || { echo "could not parse oauth state from $LOC" >&2; exit 1; }

# 2. Ask the server for a GitHub device code. This proxies to
#    GitHub's /login/device/code endpoint and returns the values we
#    need to show the user.
DEV_JSON="$(curl -sSf "$ACCESS_URL/api/v2/users/oauth2/github/device")"
DEVICE_CODE="$(printf '%s' "$DEV_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["device_code"])')"
USER_CODE="$(printf  '%s' "$DEV_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["user_code"])')"
VERIFY_URI="$(printf '%s' "$DEV_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["verification_uri"])')"
INTERVAL="$(printf   '%s' "$DEV_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("interval", 5))')"
EXPIRES_IN="$(printf '%s' "$DEV_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("expires_in", 900))')"

cat <<MSG

To sign in to Coder, open this on any device:

  $VERIFY_URI

Then enter this code:

  $USER_CODE

(Code is valid for $((EXPIRES_IN / 60)) minutes. I'll wait.)
MSG

# 3. Poll the callback. The middleware checks the cookie state
#    matches the query state and feeds the device_code through the
#    server's GithubOAuth2Config.Exchange override, which hits
#    GitHub's token endpoint. While the user hasn't entered the
#    code, the server returns 400 with detail
#    "authorization_pending"; once they have, it returns 200 with
#    {"redirect_url": "..."} and a Set-Cookie:
#    coder_session_token=... header that's the admin's session.
DEADLINE=$(( $(date +%s) + EXPIRES_IN ))
while :; do
  HTTP=$(curl -sS -o /tmp/coder-device-resp -w '%{http_code}' \
    --cookie "$JAR" --cookie-jar "$JAR" \
    "$ACCESS_URL/api/v2/users/oauth2/github/callback?code=$DEVICE_CODE&state=$STATE")
  case "$HTTP" in
    200) break ;;
    400)
      DETAIL="$(python3 -c 'import json,sys;print(json.load(open("/tmp/coder-device-resp")).get("detail",""))' 2>/dev/null || true)"
      case "$DETAIL" in
        authorization_pending|slow_down)
          [ "$DETAIL" = slow_down ] && INTERVAL=$((INTERVAL + 5))
          ;;
        expired_token|access_denied|*)
          echo "github device login failed: $DETAIL" >&2
          cat /tmp/coder-device-resp >&2
          exit 1
          ;;
      esac
      ;;
    *)
      echo "github device login: unexpected HTTP $HTTP" >&2
      cat /tmp/coder-device-resp >&2
      exit 1
      ;;
  esac
  if [ "$(date +%s)" -gt "$DEADLINE" ]; then
    echo "github device login: code expired before user entered it" >&2
    exit 1
  fi
  sleep "$INTERVAL"
done

# 4. Pull the session token out of the cookie jar and write it to
#    the directory the coder CLI reads. Two files: url and session,
#    both plain text, mode 0600. CODER_CONFIG_DIR overrides the
#    default ~/.config/coderv2.
TOKEN="$(awk '$6 == "coder_session_token" { print $7 }' "$JAR" | tail -1)"
[ -n "$TOKEN" ] || { echo "no coder_session_token in cookie jar" >&2; exit 1; }

CFG="${CODER_CONFIG_DIR:-$HOME/.config/coderv2}"
mkdir -p "$CFG"
umask 0077
printf '%s' "$ACCESS_URL" > "$CFG/url"
printf '%s' "$TOKEN"      > "$CFG/session"

# 5. Verify the CLI is signed in as the admin.
coder whoami
coder users list
```

`users list` should show exactly one row with `OWNER` in the
roles column, with the email and login from the user's GitHub
account.

## Common failures

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
- **`expired_token`.** The code's 15-minute window passed.
  Restart from step 1.
- **`State must be provided.` or `State mismatched.`** Step 1's
  cookies didn't make it to step 3, or step 3 used a different
  `state` than step 1's Location header. Reuse the same cookie
  jar across both calls and parse `state` from the redirect.
- **`PKCE challenge must be provided.`** The cookie jar doesn't
  contain `oauth_pkce_verifier`. The GitHub provider is configured
  with PKCE S256 always (see
  `coderd/userauth.go:GithubOAuth2Config.PKCESupported`); the prime
  step has to be done with a cookie jar attached so curl picks the
  cookie up. `--cookie-jar` is required on step 1; `--cookie` and
  `--cookie-jar` both pointing at it on step 3.
- **No `coder_session_token` in the jar after a 200.** Something
  changed in the server's session-cookie naming. Check the
  `Set-Cookie` headers of the 200 response directly; if a
  prefixed cookie name is used (`__Host-coder_session_token`),
  the value is still the session token. The CLI will accept
  either when written to `$CODER_CONFIG_DIR/session`.

## Why not just open a browser?

Three reasons device flow is preferred over the browser flow on
this skill:

- The install machine often has no browser (servers, CI,
  containers, headless VMs). Device flow works regardless.
- The browser flow needs `coder login`, which writes to the
  default config dir and clobbers the user's existing session if
  they're already signed in to a different deployment. Device
  flow lets us write directly to an isolated `CODER_CONFIG_DIR`.
- The user usually has a phone within reach. Punching in a short
  code is faster than tab-switching and approving an OAuth dialog
  on a desktop.

The browser flow is still appropriate when a custom GitHub OAuth
App without device flow is in effect; in that case there's no
device endpoint to drive.
