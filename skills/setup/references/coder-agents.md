# Coder Agents setup

Use this file when the user accepts the Phase 7 offer to wire up
Coder Agents, or when they ask separately to enable Coder Agents
on a Coder deployment that's already up.

Coder Agents is a self-hosted chat interface for running AI
coding agents directly inside the Coder control plane:
developers describe work, Coder picks a template, provisions a
workspace, and executes the task using a configured LLM provider
(Anthropic, OpenAI, Google, Azure, Bedrock, OpenRouter, etc.).
It's a distinct product surface from "templates" and
"workspaces" and is the primary reason a lot of teams adopt
Coder in the first place. Don't conflate it with the workspace
agent (the small `coder` process that runs inside a workspace).

## Prerequisites

Confirm before you start:

- Server version is **2.33.1 or greater**. Read it from
  `coder version --output json` or the `/api/v2/buildinfo`
  response. If the deployment is older, do not configure Coder
  Agents; tell the user the deployment needs to upgrade first.
- The calling user is an Owner of the deployment, or has
  another role with `chat:create`-equivalent permissions. The
  first user from Phase 4 is always Owner.
- The control plane has outbound network access to the chosen
  LLM provider's API. Workspaces don't; the agent loop runs in
  the control plane.
- At least one template exists with a clear description (the
  starter pushed in Phase 5 is fine for verification).

## When to offer it (Phase 7)

In the Phase 7 handoff, after the rest of the install is done,
always offer Coder Agents in plain English. Two beats: what it
is, do you want it. Do not paste a docs link.

```text
One more thing before I let you go: this version of Coder ships
with Coder Agents, a built-in chat that runs AI coding agents
inside your deployment. You describe what you want done, Coder
picks a template, spins up a workspace, and the agent does the
work (read files, run commands, edit code) while you watch.
It's self-hosted, so the LLM key and the chat history both
stay on your infrastructure.

To turn it on I'd plug your API key into Coder, configure the
latest flagship model from your provider as the default
(Anthropic's Opus or OpenAI's latest GPT, etc.), and verify
the loop works. Anthropic, OpenAI, Google, Azure OpenAI, AWS
Bedrock, OpenRouter, and any OpenAI-compatible endpoint are
supported. About 2 minutes once you've got a key. Want me to
set it up?
```

If they say yes, follow the six steps below without further
back-and-forth except for the API key paste.

## Step 1: pick the provider and take the key

Ask **one** `AskUserQuestion` to pick the provider, defaulting
to Anthropic. The supported providers are documented at
<https://coder.com/docs/ai-coder/agents/models.md#providers>;
read that page first to confirm the current list. As of this
writing they are: `anthropic`, `openai`, `google`, `azure`,
`bedrock`, `openaicompat`, `openrouter`, `vercel`.

```json
{
  "questions": [
    {
      "question": "Which LLM provider do you have a key for?",
      "header": "Provider",
      "multiSelect": false,
      "options": [
        {"label": "Anthropic", "description": "Claude models. I'll set Opus as the default."},
        {"label": "OpenAI", "description": "GPT and o-series. I'll set the latest GPT as the default."},
        {"label": "Other", "description": "Google, Azure OpenAI, AWS Bedrock, OpenRouter, Vercel AI Gateway, or any OpenAI-compatible endpoint."}
      ]
    }
  ]
}
```

If the user picks Other, ask which one in a follow-up
`AskUserQuestion` (Google / Azure OpenAI / AWS Bedrock /
OpenRouter / Vercel AI Gateway / OpenAI-compatible endpoint).

Then ask in plain English for the API key (or, for AWS
Bedrock, ask whether they want bearer-token mode or ambient
AWS credentials per
<https://coder.com/docs/ai-coder/agents/models.md#configuring-aws-bedrock>).
Confirm receipt with `[set]`; **never echo the value back** in
the chat or the shell. Pass it through environment variables
in the curl below, never on the command line.

## Step 2: confirm the API surface against the live server

The Coder Agents admin endpoints are gated by the experimental
feature flag and will move out of `/api/experimental` over
time. Always look up the actual paths the running server
exposes; **don't hard-code them from memory**. Two equivalent
ways:

- The OpenAPI spec is at `$ACCESS_URL/swagger/doc.json` and
  the interactive UI at `$ACCESS_URL/swagger`. Filter for
  paths matching `chats/providers` and `chats/model-configs`
  (or whatever the running server calls them).
- The upstream code defines the routes in
  [`coderd/coderd.go`](https://github.com/coder/coder/blob/main/coderd/coderd.go)
  (search for `Route("/providers"` near the
  `r.Route("/api/experimental/chats"` block) and the request
  schemas in
  [`codersdk/chats.go`](https://github.com/coder/coder/blob/main/codersdk/chats.go)
  (search for `CreateChatProviderConfigRequest` and
  `CreateChatModelConfigRequest`).

At the time this skill was last updated the surface was:

| What             | Method | Path                                                  |
|------------------|--------|-------------------------------------------------------|
| Create provider  | `POST` | `/api/experimental/chats/providers`                   |
| Create model     | `POST` | `/api/experimental/chats/model-configs`               |
| List providers   | `GET`  | `/api/experimental/chats/providers`                   |
| List models      | `GET`  | `/api/experimental/chats/models`                      |
| Update provider  | `PATCH`| `/api/experimental/chats/providers/{providerConfig}`  |
| Update model     | `PATCH`| `/api/experimental/chats/model-configs/{modelConfig}` |

If any of those return 404, the server moved them; consult
`/swagger/doc.json` to find the new path before continuing.

## Step 3: create the provider

`POST /api/experimental/chats/providers` with the shape
defined by `CreateChatProviderConfigRequest`:

```sh
KEY="$LLM_KEY"   # set in the agent's env, never on argv
curl -fsS -X POST \
  -H "Coder-Session-Token: $TOKEN" \
  -H 'Content-Type: application/json' \
  --data @<(python3 -c '
import json, os
print(json.dumps({
  "provider": "anthropic",          # match the user'\''s choice
  "display_name": "Anthropic",
  "api_key":  os.environ["KEY"],
  "enabled":  True,
  "central_api_key_enabled": True,
}))
') \
  "$ACCESS_URL/api/experimental/chats/providers"
```

Pick `display_name` based on the provider ("Anthropic",
"OpenAI", "Google", "AWS Bedrock", ...). For Bedrock with
ambient credentials, omit `api_key`.

## Step 4: pick the latest flagship model and create the model config

The agent should pick **one** sensible default model and mark
it `is_default`. Recommended choices:

- **Anthropic.** The latest Claude Opus model identifier. As
  of mid-2026 the newest documented identifier in the docs
  examples is `claude-opus-4-7` (also referenced as
  `claude-opus-4-6` and `claude-opus-4`); pick whichever the
  upstream model page lists as current. Anthropic publishes
  identifiers at
  <https://docs.claude.com/en/docs/about-claude/models>; read
  that page when the user picks Anthropic so you don't ship a
  stale identifier. Context limit `1000000` if the model has
  the 1M-token tier, otherwise `200000`.
- **OpenAI.** The latest GPT identifier with the largest
  context window. As of mid-2026 the docs examples reference
  `gpt-5.5` and `gpt-5.3-codex`; check OpenAI's model list at
  <https://platform.openai.com/docs/models> for the current
  identifier the user's key has access to. Context limit
  `272000` (GPT-5 series) or whatever the model card says.

When unsure which identifier is currently shipping, **read the
provider's docs page** instead of hard-coding from this file.
Place the model identifier in the `model` field exactly as the
provider expects it.

The POST body matches `CreateChatModelConfigRequest`. For
Anthropic / Opus the body looks like:

```json
{
  "provider": "anthropic",
  "model": "claude-opus-4-7",
  "display_name": "Opus (default)",
  "enabled": true,
  "is_default": true,
  "context_limit": 1000000,
  "compression_threshold": 42,
  "model_config": {
    "provider_options": {
      "anthropic": {
        "send_reasoning": true,
        "thinking": {"budget_tokens": 12000},
        "effort": "max",
        "web_search_enabled": true
      }
    }
  }
}
```

For OpenAI / GPT it looks like:

```json
{
  "provider": "openai",
  "model": "gpt-5.5",
  "display_name": "GPT-5 (default)",
  "enabled": true,
  "is_default": true,
  "context_limit": 272000,
  "compression_threshold": 70,
  "model_config": {
    "provider_options": {
      "openai": {
        "parallel_tool_calls": true,
        "reasoning_effort": "xhigh",
        "reasoning_summary": "detailed",
        "text_verbosity": "high",
        "web_search_enabled": true
      }
    }
  }
}
```

Don't carry a `cost` block from any example unless the user
gave you the prices; pricing changes constantly and incorrect
numbers in the dashboard mislead spend tracking.

`POST` the body to
`$ACCESS_URL/api/experimental/chats/model-configs` with the
admin session token and `Content-Type: application/json`.

## Step 5: grant the calling user the Coder Agents User role

Until they have it, the user can't see the **Agents** page.
The role is per-organization. The CLI command to add the role
while preserving existing roles is documented at
<https://coder.com/docs/ai-coder/agents/getting-started.md#step-2-grant-coder-agents-user>:

```sh
ORG="$(coder organizations show --selected -o json | python3 -c 'import json,sys;print(json.load(sys.stdin)["name"])')"
USER="$(coder users show me -o json | python3 -c 'import json,sys;print(json.load(sys.stdin)["username"])')"
ROLES=$(coder organizations members list -O "$ORG" -o json \
  | jq -r --arg user "$USER" \
      '.[] | select(.username == $user) | [.roles[].name, "agents-access"]
      | unique | join(" ")')
# shellcheck disable=SC2086
coder organizations members edit-roles "$USER" -O "$ORG" $ROLES
```

Owners of the deployment have it implicitly (the first user
from Phase 4 is an Owner), so the role grant only matters when
the user signed in as a non-Owner. Run the command anyway; it
is a no-op for Owners and a fix for everyone else.

## Step 6: verify

Fetch `GET /api/experimental/chats/models` and confirm exactly
one entry comes back with `is_default=true`. If the list is
empty or the default flag is missing, the model config didn't
stick; check the response body of step 4.

Then tell the user where to go in plain English:

```text
Coder Agents is wired up. Open the Agents page from your
dashboard ($ACCESS_URL/agents) and send a prompt. The default
model is the one I configured; the model selector will show
any others you add later.
```

If any step fails, say so in one sentence and offer to fall
back ("the key didn't authenticate against Anthropic's API;
want to try OpenAI or paste a different key?"). Don't dump
stack traces or expose the API key in error output.
