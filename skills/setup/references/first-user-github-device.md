# First-user sign-in via GitHub device flow

This is the scripted version of the "Sign in with GitHub" path,
for fresh deployments where the default GitHub OAuth App that
ships with the Coder server is in effect (the server log shows
`injecting default github external auth provider`, or
`/api/v2/users/authmethods` returns
`github.default_provider_configured=true`).

The default provider has GitHub's RFC 8628 device flow turned
on. That means setup can drive the whole sign-in from the
terminal: it prints a short URL and a one-time code, the user
pastes the code into github.com on whatever device is convenient
(their phone is fine), and the server polls GitHub until they
finish. No browser on the install machine, no `--first-user-*`
flags, no password to record. The first user to complete the
flow becomes the deployment Owner because of the `userCount==0`
rule in `coderd/userauth.go`.

## Critical: run this in three separate tool calls, with the
## user-facing message between them

This is the most common way the recipe is implemented wrong.

Most agent tool runners buffer a shell command's stdout and only
return it after the process exits. If you put step 1 (fetch the
code) and step 3 (poll until the user enters it) in one shell
command, the `echo` of the user code lands in the buffer, the
poll loop sits for up to 15 minutes, and the user never sees the
URL or the code. From the user's perspective, the chat just
hangs.

Run as **three** separate tool calls, in order:

1. **Fetch.** Run
   [`scripts/github-device-fetch.sh`](../scripts/github-device-fetch.sh).
   Returns in ~3 seconds. Writes `$STATE_DIR/github-device.jar`
   and `$STATE_DIR/github-device.env`.
2. **Tell the user.** Read `VERIFY_URI` and `USER_CODE` from
   `$STATE_DIR/github-device.env` and send a chat message (not a
   shell `cat` / `echo`) with those values. Wait for the user to
   acknowledge.
3. **Poll.** Run
   [`scripts/github-device-poll.sh`](../scripts/github-device-poll.sh).
   Loops until the user finishes on github.com, writes the
   session token to `$CODER_CONFIG_DIR/{url,session}`, removes
   the scratch files, and verifies with `coder whoami` and
   `coder users list`.

Do **not** combine these. Do **not** put a `cat <<MSG` or
`echo` inside the polling loop. The user only sees what the
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

## How to run each step

**Step 1: fetch.** One short tool call:

```sh
ACCESS_URL="$ACCESS_URL" \
  bash "$SKILL_DIR/scripts/github-device-fetch.sh"
```

Where `$SKILL_DIR` is the path to this skill's directory. The
script prints the contents of `$STATE_DIR/github-device.env`
(values like `USER_CODE`, `VERIFY_URI`, `EXPIRES_IN`) and exits.

**Step 2: tell the user.** Send a chat message. Read
`$STATE_DIR/github-device.env` (or parse the script's stdout
from step 1). The message should be roughly:

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

**Step 3: poll.** Run as its own command, after the user
acknowledges:

```sh
ACCESS_URL="$ACCESS_URL" \
  bash "$SKILL_DIR/scripts/github-device-poll.sh"
```

The script loops with backoff, returns when the user finishes,
writes the session token, removes the cookie jar / env / response
scratch files (success or failure), and verifies with
`coder whoami` and `coder users list`.

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
  `$STATE_DIR/github-device.env` (state value). Check that
  `$STATE_DIR` is the same across both calls.
- **`PKCE challenge must be provided.`** The cookie jar doesn't
  contain `oauth_pkce_verifier`. The GitHub provider is
  configured with PKCE S256 always (see
  `coderd/userauth.go:GithubOAuth2Config.PKCESupported`); the
  prime step must use `--cookie-jar` so curl picks up the
  cookie. The bundled `github-device-fetch.sh` does this.
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
