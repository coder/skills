# External Provisioner

Run a separate process (or pod) that polls the Coder server for
build jobs and runs Terraform, instead of letting the server itself
do it. The user-facing reasons:

- **Cloud credentials never sit on the Coder control plane.** The
  server doesn't need AWS / GCP / Azure secrets. Compromise of the
  server doesn't get the attacker into the cloud account.
- **Network isolation.** The provisioner can sit inside the VPC where
  the workspaces live; the Coder server can be in a public subnet.
  Only the provisioner needs egress to cloud APIs.
- **Scaling.** Each provisioner runs one concurrent build. Add more
  to handle parallel `coder create` calls during a demo or onboarding.
- **Build environment hardening.** Keep the server's process tree
  free of `terraform` and untrusted template code.

Running the built-in provisioner is fine for the trial path. Switch
to external as soon as the deployment serves a team or touches a
real cloud account.

## Authentication options

Three modes, in decreasing order of preference:

1. **Scoped key** (recommended). Per-provisioner key created via
   `coder provisioner keys create`. Bound to one organization and
   optionally to a tag set. Easy to rotate, easy to revoke, easy to
   audit. Requires the user be at least a Template Admin.
2. **User token**. The provisioner runs as a Template Admin or Owner
   user. Useful for automation that already has a service-account
   user; reuses that account's session.
3. **Global PSK**. One pre-shared key for every external provisioner.
   Easiest to bootstrap; impossible to rotate without coordinating
   every provisioner. Use only when the orchestrator (Helm chart,
   compose) hasn't been updated to pass scoped keys yet. Set with
   `CODER_PROVISIONER_DAEMON_PSK` on the server.

Pick scoped key unless you have a reason. The rest of this doc
assumes scoped key.

## Generate the key

On any host with `coder` installed and logged in as a Template Admin
or Owner:

```sh
coder provisioner keys create cloud-provisioner \
  --org default \
  --tag environment=cloud
```

The output prints the key once and disappears. Treat it like a
password. Capture it into a secret manager or a Kubernetes Secret
immediately.

The tag is optional. With `environment=cloud`, only build jobs whose
template is tagged the same way will run on this provisioner. That's
how you keep cloud builds off the in-server provisioner if you also
have one running.

## Run the provisioner

### Standalone (Linux VM)

```sh
export CODER_URL=https://coder.example.com
export CODER_PROVISIONER_DAEMON_KEY=<the key>

# Cloud creds the templates need.
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_REGION=us-east-1

coder provisioner start \
  --tag environment=cloud
```

Run it under systemd or a process supervisor; one process equals one
concurrent build. To support N parallel builds, run N processes (or
use `--instances N` on the same host; check `coder provisioner start
--help` for the current flag).

### Docker

```sh
docker run -d \
  --name coder-provisioner \
  --restart unless-stopped \
  -e CODER_URL=https://coder.example.com \
  -e CODER_PROVISIONER_DAEMON_KEY=<key> \
  -e AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY \
  -e AWS_REGION=us-east-1 \
  ghcr.io/coder/coder:latest \
  provisioner start --tag environment=cloud
```

For Docker-only templates, mount the host docker socket and add the
group:

```sh
  -v /var/run/docker.sock:/var/run/docker.sock \
  --group-add "$(getent group docker | cut -d: -f3)" \
```

### Kubernetes (Helm)

The chart `coder-v2/coder-provisioner` exists for this. Minimum
values:

```yaml
coder:
  env:
    - name: CODER_URL
      value: "https://coder.example.com"
    - name: CODER_PROVISIONER_DAEMON_KEY
      valueFrom:
        secretKeyRef:
          name: coder-provisioner-key
          key: key
    - name: AWS_REGION
      value: "us-east-1"
  # IRSA / Workload Identity covers AWS / GCP creds without secrets.
  serviceAccount:
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::1234:role/coder-provisioner
  replicaCount: 3
  provisionerDaemon:
    tags:
      environment: cloud
```

Install:

```sh
kubectl create secret generic coder-provisioner-key \
  --namespace coder \
  --from-literal=key="$KEY"
helm install coder-provisioner coder-v2/coder-provisioner \
  --namespace coder \
  --values provisioner-values.yaml
```

## Verify

From any client logged in as an admin:

```sh
coder provisioner list
```

The new provisioner shows up with `online` status and the tags you
set. To confirm via API:

```sh
curl -fsS \
  -H "Coder-Session-Token: $SESSION" \
  https://coder.example.com/api/v2/provisionerdaemons
```

Look for the entry with `last_seen_at` close to now.

End-to-end: push a template tagged `environment=cloud` and create a
workspace. The build should run on the external provisioner; check
with:

```sh
coder provisioner jobs list
```

The `provisioner` column should show your daemon, not the server.

## Tag both sides

The tag system gates which provisioner picks up which job. If you
tag the provisioner and not the template, the cloud provisioner sits
idle while the in-server provisioner takes the job and fails for
lack of cloud credentials. Tag both.

Push the template with matching tags:

```sh
coder templates push aws-linux \
  --provisioner-tag environment=cloud \
  --yes
```

Or set tags on the template via `coder_workspace_tags` in the
template's Terraform; the docs at
<https://coder.com/docs/admin/templates/extending-templates/workspace-tags>
cover the dynamic case.

## Common failures

- **`no provisioner daemons available` on `templates push`.** Either
  no daemon is running, or all running daemons have tag sets that
  don't match the job. Check `coder provisioner list` and confirm
  the tag set.
- **Build hangs in `pending`.** Same root cause as above; the job
  was queued but no daemon claims it.
- **`401 unauthorized` from the daemon.** The scoped key was
  rotated, the org changed, or the user behind the key was removed.
  Generate a new key and rotate the secret.
- **AWS / GCP / Azure errors during build.** The provisioner
  process doesn't have credentials in scope. Verify with `aws sts
  get-caller-identity` (or the equivalent) from inside the running
  container or VM, not from your laptop.
- **Cloud creds leaked into the audit log.** Don't pass them as
  Terraform variables or `--variable`. They land in the template
  version and the audit log. Set them on the provisioner's
  environment instead.

## When *not* to bother

- All templates run against local Docker on the same host as the
  server. The built-in provisioner is fine; an external one is just
  another moving part.
- Single-user trial install. Don't introduce two services until the
  deployment grows.

If you do skip the external provisioner now and add it later, every
template that uses cloud creds needs a `--provisioner-tag` flag at
push time, or it'll keep running on the server's in-process
provisioner.
