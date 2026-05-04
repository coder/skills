# First-User Bootstrap

The first time a Coder server runs, no users exist. The web UI's
setup page exists for this case; this skill's whole point is to do it
from the CLI.

## The canonical command

Pass the password as an env var; the other fields can be either flags
or env vars. Putting the password on the command line leaks it into
shell history and `ps` listings.

```sh
export CODER_FIRST_USER_PASSWORD="$PASSWORD"
coder login "$ACCESS_URL" \
  --first-user-email     "$EMAIL" \
  --first-user-username  "$USERNAME" \
  --first-user-full-name "$FULL_NAME" \
  --first-user-trial=false
unset CODER_FIRST_USER_PASSWORD
```

After this:

- The user exists with the Owner role in the default organization.
- A session token is in the OS keyring on macOS / Windows or in
  `~/.config/coderv2/session` on Linux.
- The server URL is in `~/.config/coderv2/url`.
- Subsequent `coder` commands authenticate automatically.

## Required flags

If you skip any of these, the CLI prompts on stdin (and hangs in
non-interactive mode) or rejects the command:

| Flag                       | Env var                        | Notes                                   |
|----------------------------|--------------------------------|-----------------------------------------|
| `--first-user-email`       | `CODER_FIRST_USER_EMAIL`       | Must be a syntactically valid email.    |
| `--first-user-username`    | `CODER_FIRST_USER_USERNAME`    | Lowercase, alphanumeric plus `-_`.      |
| `--first-user-password`    | `CODER_FIRST_USER_PASSWORD`    | At least 8 chars; API enforces complexity. |
| `--first-user-trial=false` | `CODER_FIRST_USER_TRIAL=false` | Required to suppress the trial prompt.  |

`--first-user-full-name` (env: `CODER_FIRST_USER_FULL_NAME`) is
optional but recommended. The audit log and git-author defaults read
much better with a real name.

## Trial mode

Default to **off**. Only enable it when the user explicitly asks for
"enterprise features", "premium features", or "a trial license".

When trial is on, the CLI prompts for first name, last name, phone,
job title, company, country, and developer count. Pre-collect those
and pass them via env vars before running `coder login`:

```sh
export CODER_FIRST_USER_TRIAL=true
export CODER_TRIAL_FIRST_NAME=...
# etc.
```

If you can't pre-collect them, the user will see prompts on stdin,
which won't work under headless / `claude -p`.

## Password handling

If the user has no preferred password, generate one:

```sh
PASSWORD="$(openssl rand -base64 18 | tr -d '/+=' | head -c 24)"
```

Show it to the user once at the end of Phase 7. Don't write it to a
file unless the user asked. If you must, use mode 0600 under
`~/.config/coder-install/credentials` and tell the user.

## Verifying

```sh
coder whoami
coder users list
```

`whoami` returns the bootstrapped user. `users list` shows exactly
one row with `OWNER` in the roles column.

## Common failures

- **"the initial user cannot be created in non-interactive mode"**:
  you didn't pass `--first-user-username`. The CLI uses that flag as
  the trigger for non-interactive bootstrap.
- **"context deadline exceeded" on login**: the server isn't ready
  yet. Re-run the readiness probe before retrying.
- **"403 / not authorized" on a second `coder login`**: the first
  user already exists. Use `coder login` without the
  `--first-user-*` flags, or pass `--token` if you saved the
  session.
- **CLI hangs at "Start a trial of Enterprise?"**: you forgot
  `--first-user-trial=false`. Set the flag or the env var.
- **"That's not a valid email address!"** in the password prompt:
  the CLI is in interactive mode because one of the required flags
  is missing. Re-check your invocation.

## After bootstrap

Persist nothing extra. The session token in the OS keyring (or
session file) is enough for every subsequent CLI call from the same
host. To run `coder` from a different machine, either:

- run `coder login` again from that machine (no `--first-user-*`
  flags this time), or
- create a long-lived token with `coder tokens create` and pipe it
  via `coder login --token "$TOKEN"`.
