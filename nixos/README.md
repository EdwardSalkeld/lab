## NixOS Configurations

This directory is the start of the repo-owned NixOS configuration.

Current targets:

- `partridge`: the first repo-managed NixOS VM.

## Installing Packages

On the current manually installed VM, the immediate path is to edit
`/etc/nixos/configuration.nix` and run:

```sh
sudo nixos-rebuild switch
```

For a permanent system package, add it to `environment.systemPackages` in
the system configuration:

```nix
environment.systemPackages = with pkgs; [
  git
  htop
  vim
];
```

After a host is adopted into this repo, add shared packages to
`nixos/modules/proxmox-vm-base.nix`, then rebuild the host. For `partridge`:

```sh
sudo nixos-rebuild switch --flake .#partridge
```

For a temporary shell with a package:

```sh
nix shell nixpkgs#htop
```

For a user-profile package that is not part of the system config:

```sh
nix profile install nixpkgs#htop
```

Prefer `environment.systemPackages` for lab infrastructure so the machine can
be recreated from the repo.

## Deploying `partridge`

From a checkout on `partridge`:

```sh
./scripts/nixos-switch.sh
```

The script uses `hostname -s` to select the matching flake target. It also
accepts other `nixos-rebuild` actions:

```sh
./scripts/nixos-switch.sh dry-build
./scripts/nixos-switch.sh build
./scripts/nixos-switch.sh test
./scripts/nixos-switch.sh boot
```

From another machine with SSH access:

```sh
nixos-rebuild switch --flake .#partridge --target-host edward@partridge --use-remote-sudo
```

## Prometheus Exporters

All Proxmox VM hosts include node exporter on port `9100` from
`nixos/modules/proxmox-vm-base.nix`.

`partridge` also exposes PostgreSQL metrics on port `9187`. The exporter runs
locally as the `postgres` Unix user, so it does not need a database password.

Example Prometheus scrape config:

```yaml
- job_name: partridge-node
  static_configs:
    - targets: ["partridge:9100"]

- job_name: partridge-postgres
  static_configs:
    - targets: ["partridge:9187"]
```

After switching the host, verify both endpoints:

```sh
curl http://partridge:9100/metrics
curl http://partridge:9187/metrics
```

## Tailscale

`partridge` runs Tailscale for remote access over the tailnet. After the first
switch that enables it, authenticate the machine once:

```sh
sudo tailscale up
```

Once authenticated, connect over the tailnet with normal SSH:

```sh
ssh edward@partridge
```

## HTTPS on `partridge`

`partridge` serves a small Nginx landing page at:

```text
https://partridge.int.alcachofa.faith
https://partridge.ts.alcachofa.faith
```

TLS certificates are issued by Let's Encrypt through the NixOS ACME module
using Cloudflare DNS-01 validation.

Before switching this config for the first time, create the Cloudflare token
environment file on `partridge`:

```sh
sudo install -d -m 0700 /var/lib/secrets
sudo install -m 0600 /dev/null /var/lib/secrets/acme-cloudflare.env
sudoedit /var/lib/secrets/acme-cloudflare.env
```

The file should contain:

```sh
CF_DNS_API_TOKEN=your_cloudflare_token_here
```

The token needs Cloudflare `Zone:Read` and `DNS:Edit` permissions for the zone.
DNS also needs to point `partridge.int.alcachofa.faith` and
`partridge.ts.alcachofa.faith` at addresses reachable by the clients that will
use them.

## Forgejo on `partridge`

Forgejo is served at:

```text
https://code.alcachofa.faith
```

It stores app state and repositories under `/srv/code/forgejo` on the dedicated
`partridge-code` disk. Its database is Postgres, using the local PostgreSQL
service backed by `/var/lib/postgresql`. SSH clone support is disabled for now;
use HTTPS remotes.

Registration is disabled. After the first switch, create an admin user from the
host:

```sh
sudo -u forgejo forgejo admin user create \
  --config /srv/code/forgejo/custom/conf/app.ini \
  --work-path /srv/code/forgejo \
  --username edward \
  --email admin@alcachofa.faith \
  --password 'replace-me' \
  --admin \
  --must-change-password=false
```

DNS needs `code.alcachofa.faith` to resolve to the host, currently by CNAME to
`partridge.ts.alcachofa.faith`.

## Vaultwarden on `partridge`

Vaultwarden is served at:

```text
https://vault.alcachofa.faith
```

It stores data under `/var/lib/vaultwarden` on the dedicated `vaultwarden`
disk. This first-pass configuration allows signups so you can create the
initial account. After that account exists, flip
`SIGNUPS_ALLOWED` to `false` in `nixos/hosts/partridge/vaultwarden.nix`.

After Terraform adds the disk, format it once before switching the NixOS config:

```sh
sudo mkfs.ext4 -F /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi3
```

DNS needs `vault.alcachofa.faith` to resolve to the host, currently by CNAME to
`partridge.ts.alcachofa.faith`.

## Bitwarden Mirror

`partridge` has a nightly `bitwarden-vaultwarden-mirror.timer` that refreshes
the Vaultwarden personal vault from Bitwarden cloud using the repo-packaged
`bitwarden-mirror` Go tool and the upstream `bw` CLI.

The refresh is intentionally destructive: it lists destination personal-vault
items and folders, permanently deletes items first and folders second, then
imports a fresh Bitwarden JSON export. The temporary plaintext export lives in
`/run/bitwarden-mirror` and is removed on success and failure.

Secrets are expected in `nixos/hosts/partridge/secrets/bitwarden-mirror.yaml`
as a sops-encrypted document with the keys shown in the adjacent `.example`
file. Replace the placeholder Partridge recipient in `.sops.yaml` with the
host age recipient before encrypting real credentials.

## Building An Image Later

NixOS can build images from normal system configurations with:

```sh
nixos-rebuild build-image --image-variant proxmox --flake .#image-name
```

This repo also exposes direct build outputs:

```sh
nix build .#image-name
```

`proxmox-vma` should be the native Proxmox backup/archive image format.
`proxmox-qcow-efi` is useful if importing a disk into an existing Terraform VM
is easier than restoring a VMA.

Run these from a machine with Nix installed. The Mac-side workspace currently
does not have the `nix` command available, so image builds need to happen from
the NixOS VM or another Nix builder.
