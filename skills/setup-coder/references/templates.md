# Starter Template Matrix

Use `coder templates init --id <id> <dir>` to scaffold a template into
a working directory, then `coder templates push <name>` to publish it.

`coder templates init --help` lists the canonical IDs.

## Pick by infrastructure

| Install target              | Template ID               | Required parameters / variables       |
|-----------------------------|---------------------------|---------------------------------------|
| Local Docker                | `docker`                  | None                                  |
| Local Docker, devcontainers | `docker-devcontainer`     | None                                  |
| Local Docker, envbuilder    | `docker-envbuilder`       | None                                  |
| Kubernetes                  | `kubernetes`              | `namespace`, `use_kubeconfig`         |
| Kubernetes, devcontainer    | `kubernetes-devcontainer` | `namespace`                           |
| AWS EC2 Linux               | `aws-linux`               | `region`, IAM role / credentials      |
| AWS EC2 Windows             | `aws-windows`             | `region`, IAM role / credentials      |
| AWS devcontainer            | `aws-devcontainer`        | `region`, IAM role / credentials      |
| GCP Compute Linux           | `gcp-linux`               | `project_id`, `zone`                  |
| GCP devcontainer            | `gcp-devcontainer`        | `project_id`, `zone`                  |
| GCP VM container            | `gcp-vm-container`        | `project_id`, `zone`                  |
| GCP Windows                 | `gcp-windows`             | `project_id`, `zone`                  |
| Azure Linux                 | `azure-linux`             | `subscription_id`, `location`         |
| DigitalOcean droplet        | `digitalocean-linux`      | DO API token                          |
| Nomad                       | `nomad-docker`            | Nomad address                         |
| Incus                       | `incus`                   | Incus socket / remote                 |
| Tasks (Coder Tasks)         | `tasks-docker`            | None                                  |
| Bare scratch (advanced)     | `scratch`                 | Author the resource yourself          |

## Default mapping

When the install target is already chosen in Phase 1, default the
template like this:

- Standalone install on a Linux box with Docker available: `docker`.
- Standalone install with no Docker: tell the user they need either
  Docker, an envbuilder runtime, or a cloud account before a workspace
  will build. Don't push a template that will fail.
- Docker compose deployment: `docker`.
- Kubernetes (Helm): `kubernetes`.
- Cloud VM provisioning: the matching cloud template.

## Provider credentials

Cloud templates need real credentials before `coder templates push`
will succeed (or before the first workspace build, depending on the
template's variable layout). Collect them with the user before
running `push`.

For AWS:

- The recommended path is an instance role on the EC2 host running
  `coder server`. The provisioner inherits that role.
- Otherwise set `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and
  `AWS_REGION` in the environment of `coder server` (not the CLI).
- Don't put credentials in `terraform.tfvars`; they leak into every
  template version.

For GCP:

- Use a service account JSON file mounted to the server. Set
  `GOOGLE_APPLICATION_CREDENTIALS` in the server environment.

For Azure:

- Use a Service Principal. Set `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`,
  `ARM_SUBSCRIPTION_ID`, `ARM_TENANT_ID` in the server environment.

## Variables files

Pass non-secret template variables with `--variables-file`. The format
is YAML key/value pairs (parsed by
`codersdk.ParseUserVariableValues`):

```sh
cat > /tmp/vars.yaml <<EOF
namespace: coder
use_kubeconfig: false
EOF
coder templates push my-template --variables-file /tmp/vars.yaml --yes
```

You can also pass values from the command line with repeated
`--variable name=value` (alias `--var`).

## After push

Verify with:

```sh
coder templates list
coder templates versions list <name>
```

If the active version is in `failed` state, read the build logs:

```sh
coder templates versions list <name>
```

The error from Terraform / the provisioner is printed there. Fix the
template variables or provider configuration and run `templates push`
again.
