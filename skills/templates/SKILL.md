---
name: templates
description: >
  Create, edit, push, or version a Coder template. Use for requests
  like "scaffold a Docker template", "build a Kubernetes template",
  "add a coder_parameter for the Git repo URL", "push my template to
  this Coder deployment", "update the existing aws-linux template to
  add JetBrains", or "deprecate this template version". Do not use
  for installing or upgrading Coder itself (use the setup skill),
  adding a single module to a template that already builds (use the
  modules skill), or authoring custom Terraform providers unrelated
  to Coder.
---

# Templates

Author or update Coder templates. A template is Terraform code that
Coder runs to build a workspace; one template can back many
workspaces.

## Source of Truth

Read current upstream docs before applying anything topic-specific:

- <https://coder.com/docs/llms.txt> for the docs index.
- <https://coder.com/docs/llms-full.txt> only when the index is not
  enough.
- <https://registry.coder.com/templates> for the canonical starter
  templates and their import IDs.

This skill keeps only the authoring workflow, user interaction rules,
and a few template-specific gotchas.

## User Interaction

The user wants a working workspace, not a Terraform crash course.

- Default to a sensible starter for their infrastructure. Ask only to
  confirm.
- Show the planned tree (template name, files, parameters) before
  writing anything. Ask for one yes/no.
- Do not ask for cloud credentials in chat. Use the deployment's
  provisioner authentication; bring it up only when it is missing.

## Workflow

### 1. Pick a starter

Map the user's intent to one of the official starters at
<https://registry.coder.com/templates>:

- `docker`, `docker-devcontainer`, `docker-rstudio`: container hosts.
- `kubernetes`, `kubernetes-devcontainer`, `kubernetes-envbox`: K8s
  clusters.
- `aws-linux`, `aws-windows`, `aws-devcontainer`: AWS EC2.
- `gcp-linux`, `gcp-windows`, `gcp-vm-container`, `gcp-devcontainer`:
  GCP Compute Engine.
- `azure-linux`, `azure-windows`: Azure VMs.
- `digitalocean-linux`: DigitalOcean Droplets.
- `incus`: LXD/Incus containers.
- `nomad-docker`: Nomad-driven Docker.
- `scratch`: empty template for advanced authors only.

Scaffold the chosen starter:

```sh
TEMPLATE_DIR="$(mktemp -d)/$TEMPLATE_NAME"
coder templates init --id "$STARTER_ID" "$TEMPLATE_DIR"
```

For an existing template the user wants to edit, pull instead:

```sh
TEMPLATE_DIR="$(mktemp -d)/$TEMPLATE_NAME"
coder templates pull "$TEMPLATE_NAME" "$TEMPLATE_DIR"
```

### 2. Understand the template anatomy

Every Coder template has these moving parts in `main.tf`:

- `terraform` block: required providers (always `coder/coder`, plus
  the infrastructure provider).
- `data "coder_workspace" "me"` and `data "coder_workspace_owner"
  "me"`: workspace context, including `start_count`.
- `data "coder_parameter"` blocks: user inputs at workspace creation.
- One `coder_agent` resource: the agent that runs inside the
  workspace.
- `coder_app` resources: dashboard buttons for VS Code, JetBrains,
  Jupyter, and similar apps.
- Infrastructure resources: `docker_container`,
  `kubernetes_deployment`, `aws_instance`, etc., depending on the
  starter.
- Optional `module` blocks: Coder modules from registry.coder.com.

### 3. Modify

Apply the change the user asked for. Common patterns:

- Add `coder_parameter`s. Set `mutable = true` when the value should
  be changeable on rebuild. Use `validation` blocks for regex or
  range enforcement. Use `option` blocks for enums.
- Add modules from <https://registry.coder.com/modules>. Defer
  module-specific syntax to the modules skill or to the module
  README.
- Persist data with a dedicated volume resource keyed to the
  workspace owner. Do not rely on container or VM filesystems to
  survive a rebuild.
- Set `count = data.coder_workspace.me.start_count` on resources that
  should be torn down when the workspace stops.

Never store secrets in `terraform.tfvars` or pass them via plain
`--variable`. Use Coder's secret variables or external provisioners.

### 4. Validate locally

```sh
cd "$TEMPLATE_DIR"
terraform init
terraform fmt
terraform validate
```

### 5. Push

First push:

```sh
coder templates create "$TEMPLATE_NAME" -d "$TEMPLATE_DIR" --yes
```

Update an existing template:

```sh
coder templates push "$TEMPLATE_NAME" -d "$TEMPLATE_DIR" --yes
coder templates versions list "$TEMPLATE_NAME"
```

Promote the new version with `--activate` on push, or afterwards with
`coder templates versions promote`.

### 6. Test

Create one workspace from the new version:

```sh
coder create "$WORKSPACE_NAME" \
  --template "$TEMPLATE_NAME" \
  --yes
```

Pass every required parameter explicitly. For list parameters with no
sensible value, use `[]`. For enums, use the first option. Ask the
user only when no default makes sense.

Wait until the agent reaches `ready`, not just until the build
finishes. If the agent stays in `connecting`, the workspace cannot
be used.

### 7. Hand off

If this was the user's first template, end with:

- Where the template lives in the dashboard.
- One workspace name they can run `coder ssh` into.
- One sentence about updates: edit `main.tf`, then
  `coder templates push`.

## Common Parameters

Worth knowing because users ask for them often:

- `git_repo_url`: URL to clone on workspace start. Pair with the
  `git-clone` module.
- `region`: provider-specific region picker. Pair with the matching
  `*-region` module.
- `instance_type` or `node_size`: provider-specific machine size with
  an `option` list.
- `dotfiles_uri`: clone a personal dotfiles repo on start. Pair with
  the `dotfiles` module.
- `vscode_binary_version`: optional pin for `code-server`.

## variable vs. coder_parameter

Use a Terraform `variable` (set via `--variable` at `coder templates
push` time) for **infrastructure-level** choices that are fixed for
the entire template deployment and set by the admin:

- CPU architecture of the host machine (`arch`)
- Storage pool or volume group name
- Remote host identifier or cluster endpoint

Use `data "coder_parameter"` for choices the **workspace user** makes
at creation or build time:

- OS image or distribution
- CPU count, memory, and disk size
- Any value that legitimately differs between workspaces

Never expose infrastructure details as `coder_parameter`. Users
should not need to know the host's CPU architecture or the name of
a storage pool.

```terraform
# Good: arch is an admin concern, not a user choice
variable "arch" {
  description = "CPU architecture of the VM host (amd64 or arm64). Set at template push time."
  type        = string
  default     = "amd64"
}

# Good: image is a user choice made per workspace
data "coder_parameter" "image" {
  name    = "image"
  type    = "string"
  default = "ubuntu/noble/cloud"
  option {
    name  = "Ubuntu 24.04 LTS"
    value = "ubuntu/noble/cloud"
  }
}
```

Pass `variable` values at push time:

```sh
coder templates push my-template -d . --yes \
  --variable arch=arm64 \
  --variable storage_pool=fast-nvme
```

## Deprecated coder_agent Fields

Do not set `dir` on `coder_agent`. It is deprecated in recent
provider versions, generates warnings on every `coder templates push`,
and breaks Coder Desktop file sync. The agent always starts in
`$HOME` by default.

```terraform
# Wrong: deprecated, causes warnings
resource "coder_agent" "main" {
  dir = "/home/${local.username}"
}

# Correct: omit dir entirely
resource "coder_agent" "main" {
  arch = var.arch
  os   = "linux"
}
```

## Contributing Templates to coder/registry

Before opening a PR, read the registry's
[AGENTS.md](https://github.com/coder/registry/blob/main/AGENTS.md)
for code style, structure requirements, and the full PR review
checklist. Also read the
[PR template](https://github.com/coder/registry/blob/main/.github/PULL_REQUEST_TEMPLATE.md)
for the required PR body format.

Additional points specific to templates (not covered in AGENTS.md):

- Templates live at `registry/<namespace>/templates/<name>/` with
  `main.tf` and `README.md`. No `.tftest.hcl` is required (only
  modules need tests).
- PR title convention: `feat(<namespace>/templates/<name>): <short
  description>` (e.g. `feat(bpmct/templates/incus-vm): add Incus VM
  template`).
- **Sync your fork's `main` with upstream before branching.**
  If you don't, the PR diff will show all pre-existing files in your
  namespace as new additions rather than just your changes:

  ```sh
  gh api -X POST /repos/<your-username>/registry/merge-upstream \
    -f branch=main
  ```

- Run `bun fmt` (which runs `terraform fmt` + Prettier) and confirm
  it produces no diff before pushing.

## Safeguards

- Do not push a template version that has not passed `terraform
  validate`.
- Do not archive or delete an active template version without
  confirming nothing depends on it.
- Do not pass `--activate` on `coder templates push` if the user is
  still iterating. They may want to review the new version first.
- Do not place cloud credentials, OAuth secrets, or workspace tokens
  in `main.tf` or `terraform.tfvars`. Use secret variables.
- Do not recommend `scratch` to a user who does not already author
  Terraform.

## Bundled Resources

No per-template recipes ship with this skill. Defer to each
template's README on registry.coder.com and to upstream Coder docs
for provider-specific detail.
