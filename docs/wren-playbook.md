# Wren Playbook

This is the canonical playbook for tearing down and recreating `wren` as the
repo's disposable zero-touch Debian VM.

Use this when the goal is: create a fresh VM in Proxmox, get Billy SSH access,
join the tailnet without browser interaction, and serve the hello page.

## Success Criteria

At the end of a successful run:

- Terraform has created or replaced the Proxmox VM named `wren`
- `billy@wren` works either on the LAN IP or over Tailscale
- `tailscale status` shows `wren` joined with the intended tag set
- nginx serves `Hello from wren`

## Preconditions

Before starting, make sure these are already true:

- Terraform credentials are available in `terraform/.env`
- `partridge` has already switched to a config that includes
  `nixos/hosts/partridge/deploy-trigger.nix` from current `main`
- GitHub Actions secrets exist:
  - `TS_OAUTH_CLIENT_ID`
  - `TS_OAUTH_SECRET`
  - `PARTRIDGE_DEPLOY_SSH_KEY`
  - `WREN_BILLY_SSH_KEY`
- The Tailscale OAuth client is allowed to advertise the tag set you plan to
  use. The safe default is `tag:ci`.

## Design Rules

These are the guardrails that keep this path from falling back into the same
failure modes:

- Use the Debian generic cloud image with Proxmox native cloud-init.
- Keep `wren` on DHCP.
- Keep boot shape close to the minimal Proxmox cloud-image example:
  SeaBIOS, imported `virtio0` root disk, serial console.
- Treat boot-shape changes as replace-only, not in-place mutation.
- Do not depend on Proxmox snippet uploads or Proxmox-host root SSH.
- Once the VM is reachable, prefer direct guest SSH debugging over more deploy
  indirection.

## Canonical Rebuild Flow

### 1. Start from current `main`

```sh
git fetch origin
git checkout main
git pull --ff-only
```

If you are making repo changes as part of the rebuild, branch from current
`main` first.

### 2. Confirm the expected `wren` shape in Terraform

The expected implementation is in `terraform/hello-vm.tf` and `terraform/locals.tf`.
Before applying, confirm it still has these properties:

- `proxmox_virtual_environment_vm.wren_recreated`
- DHCP in `initialization.ip_config.ipv4.address = "dhcp"`
- `billy` user keys from `billy_public_ssh_keys` and `public_ssh_keys`
- imported root disk on `virtio0`
- serial console via `serial_device {}` and `vga { type = "serial0" }`
- lifecycle replacement driven by `terraform_data.wren_replace_signature`

If Terraform is about to migrate the root disk controller or boot profile
in place, stop and make it a replacement instead.

### 3. Apply Terraform

```sh
set -a
source terraform/.env
set +a
terraform -chdir=terraform plan
terraform -chdir=terraform apply
```

Expected outcome:

- the old disposable VM is destroyed and recreated when needed
- the new VM appears in Proxmox as `wren`
- cloud-init creates the `billy` account with the repo-managed SSH keys

### 4. Bootstrap the guest through the manual GitHub workflow

Run the `bootstrap wren direct` workflow with the default input:

- `advertise_tags=tag:ci`

What this workflow does:

- joins the GitHub runner to the tailnet as `tag:ci`
- SSHes to `deploy@partridge.ts.alcachofa.faith`
- asks `configure-wren` to find `wren` by LAN DNS first, then by trying Billy's
  SSH key directly against reachable `10.4.1.0/24` SSH responders
- installs nginx and Tailscale on `wren`
- clears any stale interactive Tailscale login state
- runs `tailscale up --client-id=... --client-secret=...`

This is the canonical zero-interaction join path. Do not fall back to a browser
auth URL unless the OAuth path itself is broken.

### 5. Verify the result directly

Verify from a shell with Billy's key:

```sh
ssh billy@wren.tailb35748.ts.net hostname
ssh billy@wren.tailb35748.ts.net systemctl is-active nginx tailscaled
curl http://wren.tailb35748.ts.net
```

Also verify locally on the box if needed:

```sh
tailscale status
hostname
systemctl is-active nginx tailscaled
cat /var/www/html/index.html
```

## Troubleshooting

### Terraform wants to mutate boot disks in place

Symptom:

- Proxmox rejects apply with errors around deleting `scsi0` or changing the boot
  disk/controller layout

Response:

- do not keep patching around the in-place mutation
- make the change replacement-only through the `wren_replace_signature` path or
  a one-time resource-address move if required

### `bootstrap wren direct` still behaves like old code

Symptom:

- the workflow keeps failing on an old DNS-only path or other stale behavior

Response:

- remember that the workflow SSHes to live `partridge` and runs the deployed
  `configure-wren` forced command
- changing `nixos/hosts/partridge/deploy-trigger.nix` in Git alone does nothing
  until `partridge` has switched to that repo state

### Tailscale rejects the requested tag

Symptom:

- `tailscale up` fails with `requested tags [...] are invalid or not permitted`

Response:

- use a tag the OAuth client is allowed to advertise
- the safe default for this path is `tag:ci`

### `tailscale up` is stuck in interactive login state

Symptom:

- `tailscale status` shows `NeedsLogin` after an earlier manual or interactive
  attempt

Response:

Clear the stale state before retrying:

```sh
pkill -f 'tailscale up' || true
tailscale logout || true
systemctl restart tailscaled
```

Then rerun the non-interactive OAuth join.

### `wren` never appears in DNS

Symptom:

- `wren` and `wren.int.alcachofa.faith` do not resolve

Response:

- DNS is helpful but not required for this playbook
- the live `configure-wren` path already falls back to discovering the guest by
  trying Billy's SSH key against reachable LAN SSH responders
- if the VM still cannot be found, debug whether the guest actually booted and
  requested DHCP rather than adding more DNS-first logic

## When To Debug Directly

Once Billy SSH access works to the guest, stop routing service bring-up through
extra deploy loops unless the point of the work is to improve the shared
automation itself.

For disposable `wren` work, direct SSH is the shortest source of truth for:

- confirming cloud-init completion
- checking the real LAN IP
- inspecting `tailscaled` state
- verifying nginx content

## Files That Define This Path

- `terraform/hello-vm.tf`
- `terraform/locals.tf`
- `.github/workflows/bootstrap-wren-direct.yml`
- `nixos/hosts/partridge/deploy-trigger.nix`

