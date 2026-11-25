## NixOS Configurations

This directory holds the NixOS configuration for every host in the root
flake's `nixosConfigurations`:

- `partridge`: monitoring, PostgreSQL, Forgejo and Vaultwarden VM on `sol`.
- `magpie`: chatting and Forgejo runner VM on `sol`.
- `kite`: media VM on `luna` for Jellyfin, Navidrome, MPD, Photoview and MCM.
- `falcon`: Hetzner Cloud host for FreshRSS and the public proxies.

Shared modules are under `modules/`. The Proxmox VMs import
`modules/lab-base.nix` (users, SSH, sudo, Nix settings, node exporter and the
shared package list) and `modules/proxmox-guest.nix` (boot loader, QEMU guest
agent, fstrim and DHCP). Falcon is not a Proxmox guest and still keeps its own
copy of the lab-base settings. Each host sets its own `system.stateVersion`.
[AGENTS.md](../AGENTS.md#hosts) has the full host table.

## Installing Packages

For a permanent system package, add it to `environment.systemPackages` in
the host's configuration under `nixos/hosts/<host>/`:

```nix
environment.systemPackages = with pkgs; [
  git
  htop
  vim
];
```

Packages every Proxmox VM needs go in `nixos/modules/lab-base.nix`;
Falcon keeps its own list in `nixos/hosts/falcon/configuration.nix`. Merging
the change to `main` deploys it.

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

## Switching a host by hand

The normal deploy is the GitHub workflow below. To switch by hand from a
checkout on a host:

```sh
./scripts/nixos-switch.sh
```

The script uses `hostname -s` to select the matching flake target. It also
accepts other `nixos-rebuild` actions plus a `rollback` shortcut for
`nixos-rebuild switch --rollback`:

```sh
./scripts/nixos-switch.sh dry-build
./scripts/nixos-switch.sh build
./scripts/nixos-switch.sh test
./scripts/nixos-switch.sh boot
./scripts/nixos-switch.sh rollback
```

From another machine with SSH access, for example to `partridge`:

```sh
nixos-rebuild switch --flake .#partridge --target-host edward@partridge --use-remote-sudo
```

The next deploy from `main` replaces anything switched by hand.

## Installing `magpie`

`magpie` runs chatting. Terraform creates it as a blank VM with the NixOS ISO
attached, like the other Proxmox VMs. Use
[install-vm-runbook.md](./install-vm-runbook.md) for the install flow: use the
Proxmox console only to set a temporary root password and start `sshd`, then
finish partitioning and installing over SSH.

The checked-in hardware config expects these filesystem labels:

- `nixos`: root filesystem
- `BOOT`: EFI filesystem
- `workspace`: the `scsi1` workspace disk, mounted at `/srv/chatting/workspace`
- `dockerdata`: the `scsi2` CI disk, mounted at `/var/lib/docker` for the
  Forgejo runner

Use those labels during the install, or replace
`nixos/hosts/magpie/hardware-configuration.nix` with the generated file. Format
the two data disks once before relying on them, finding each blank disk by its
Terraform serial (`magpie-workspace`, `magpie-ci`):

```sh
lsblk -o NAME,SIZE,FSTYPE,LABEL,SERIAL
sudo mkfs.ext4 -L workspace /dev/sdX
sudo mkfs.ext4 -L dockerdata /dev/sdY
```

Both are mounted `nofail`, so the host still boots without them.
`terraform/README.md` covers growing the root and workspace disks.

### `chatting` services on `magpie`

`chatting.target` groups three systemd services:

- `chatting-bbmb.service`
- `chatting-handler.service`
- `chatting-worker.service`

Nix builds the runtime from the pinned `chatting` and `bbmb` flake inputs and
renders `/etc/chatting/handler.json`, `/etc/chatting/worker.json` and the
sops-backed secret env files. Service state lives under
`/var/lib/{bbmb,handler,worker}` and the worker's workspaces under
`/srv/chatting/workspaces`. [Chatting on Lab](../docs/chatting.md) covers
upgrades, services, retention and webhook ingress.

### Recovering Codex login on `magpie`

If incoming messages stop getting replies while all three chatting services are
active, run this from the lab repo on a machine connected to the tailnet:

```sh
./scripts/magpie-codex-reauth.sh
```

The script shows recent worker failures, SSHes to `edward@magpie`, runs device
login as the shell-less `worker` user, then checks the new login with a real
read-only Codex request. An `execution_error` with `401 Unauthorized` or
`invalidated oauth token` indicates that reauthentication is needed. Open the
URL printed by Codex, sign in, and enter its one-time code. Device code login
must be enabled in the ChatGPT account or workspace settings.

The credentials are stored in `/var/lib/worker/.codex/auth.json`; do not print
or copy them into logs, tickets, or the repo. `codex login status` only confirms
that credentials are present and can report a login even when the token has
been invalidated. No service restart is needed: the worker starts a fresh Codex
process for each task. Messages already marked `execution_error` are not
automatically retried; resend any needed requests after login succeeds.

## GitHub Deploy Workflow

On pushes to `main`, the `deploy` workflow first builds and publishes the
system closure of every host in the flake's `nixosConfigurations` from the
exact commit. It then joins Tailscale as
`tag:ci`, SSHes to `deploy@fourth.ts.alcachofa.faith`, and asks the orchestrator
to run `apply-terraform` followed by a pinned, cache-only `nix-switch`. See
[`docs/ci-built-nixos-deploy.md`](../docs/ci-built-nixos-deploy.md) for cache
setup and bootstrapping a host by hand.

On pull requests that touch Terraform, CI uses the same route to ask fourth to
run `plan-terraform <pr-number> <head-sha>`. Fourth fetches that PR ref into a
temporary directory, sources `/var/lib/deploy/creds/lab.env` through the deploy
dispatcher, and runs `terraform plan` locally against the private Proxmox APIs
while keeping Terraform state in Terraform Cloud.

Terraform plans and applies take a shared lock on fourth so a PR plan cannot run
through the local Terraform checkout at the same time as a main-branch apply.

Required GitHub Actions secrets:

- `TS_OAUTH_CLIENT_ID`: Tailscale OAuth client ID with `auth_keys` scope
- `TS_OAUTH_SECRET`: Tailscale OAuth client secret
- `FOURTH_DEPLOY_SSH_KEY`: private key matching the repo-declared deploy key on
  `fourth`
- `LAB_NIX_CACHE_AUTH_TOKEN`: write token for the Lab Cachix cache

Required repository variables: `LAB_NIX_CACHE_NAME` and
`LAB_NIX_CACHE_PUBLIC_KEY`.

The Tailscale ACL should allow `tag:ci` to reach `fourth`'s Tailscale SSH
endpoint. The first deployment of this wiring must still be applied manually so
the `deploy` user and forced command exist before the workflow can connect.

The manually triggered `nix-gc` workflow uses the same restricted path. Choose
a host when dispatching it; fourth runs `deploy/nix-gc-<host>.sh`, which asks
the selected host to start its configured `nix-gc.service` and logs root
filesystem usage before and after collection.

CI builds and deploys whatever hosts the flake defines, but fourth only acts on
the fixed host lists in `deploy/nix-switch.sh` and `deploy/nix-gc.sh`, since
they are the boundary for what a CI request can reach. When adding or removing
a host, also update those lists, the `nix-gc-<host>.sh` wrappers and the
`nix-gc` workflow's choices. `scripts/check-host-lists.py` fails CI until they
all match the flake.

The July 2026 `wren` bootstrap experiment has been torn down. Keep `partridge`
focused on its normal service role until the next disposable VM path is
reintroduced in a dedicated branch.

## Prometheus Exporters

All Proxmox VM hosts include node exporter on port `9100` from
`nixos/modules/lab-base.nix`.

`partridge` also exposes PostgreSQL metrics on port `9187`. The exporter runs
locally as the `postgres` Unix user, so it does not need a database password.

`partridge` runs Prometheus on port `9090`, backed by a dedicated
`prometheus` disk mounted at `/var/lib/prometheus`. The first Prometheus copy
was sized from Blink's existing Docker volume, which used about 5.1 GiB, so the
Partridge disk starts at 10 GiB.

After Terraform adds the disk, format it once before switching the NixOS config:

```sh
sudo mkfs.ext4 -F /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi4
```

The scrape config covers the active lab hosts and their exported metrics.

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
curl http://partridge:9090/-/ready
```

## PostgreSQL Backups

`partridge` dumps all local PostgreSQL databases to `/var/backup/postgresql`
daily at 02:00 and backs that directory up to a dedicated Backblaze B2 restic
repository at 03:00. Retention keeps 3 daily and 4 weekly snapshots of each
host and path group, so it also prunes the Forgejo snapshots in the same
repository. A restic check with `--read-data-subset=10%` runs weekly on
Wednesday at 05:15.

The Backblaze/restic credentials live in:

```text
nixos/hosts/partridge/secrets/postgres-backup.yaml
```

Edit them with `sops` before deploying real backups. The required values are
shown in `postgres-backup.yaml.example`.

Useful commands on `partridge`:

```sh
sudo systemctl start postgresqlBackup.service
sudo systemctl start restic-backups-partridge-postgres.service
sudo restic-partridge-postgres snapshots
```

## Kite Data Backups

Kite owns the off-site archive for its data disk. Native NixOS Restic archives
`/data/full` to the existing Backblaze B2 repository using the encrypted
`nixos/hosts/kite/secrets/kite-backup.yaml` credentials imported from Fourth. This
implements the off-site part of [house#120](https://github.com/brokensbone/house/issues/120).
Fourth remains outside Lab control and continues to pull the local recovery
copy itself; Kite never opens a connection to Fourth.

The weekly schedule is unchanged: backup Monday 06:30, prune Tuesday 04:00,
and a check reading 10% of repository data Wednesday 05:15, all Europe/London.
Retention remains three latest, seven daily, five weekly and twelve monthly
snapshots. The `*.tmp` exclusion and `dataplan` tag are preserved.

The backup unit privately bind-mounts `/data/full` read-only at `/mnt/volumes`
and keeps the logical snapshot host `docker`. Those are the legacy archive's
identity, not the machine running the job. Keeping them allows automatic
parent selection and retention to continue across the move. Restic's
repository-wide content deduplication also works across hosts; the first Kite
run may reread files because the source disk's inode/ctime metadata differs
from Fourth's rsynced copy. It uploads only content absent from the repository.
The unit requires the `/data` mount and never initializes a new repository.

Pruning is scoped to that host/path/tag and skips until Kite has completed a
successful backup. Its timer has no catch-up run during initial activation.
Grafana includes both Kite's journal and Fourth's historical container logs
through the hand-off; rsync monitoring remains unchanged.

After deployment, run and verify the first backup before retiring Fourth's
`backup`, `prune` and `check` containers. Check the snapshot and retention plan,
restore a small file, and confirm the completion marker reaches Loki:

```sh
sudo systemctl start restic-backups-kite-full.service
sudo restic-kite-full snapshots --host docker --path /mnt/volumes --tag dataplan
sudo restic-kite-full forget --dry-run --host docker --path /mnt/volumes --tag dataplan \
  --keep-last 3 --keep-daily 7 --keep-weekly 5 --keep-monthly 12
```

Keep Fourth's rsync pull running; moving the local copy transport is a separate
part of house#120. Restoring the old containers with the preserved Fourth
credentials remains the rollback path until the migration is verified.

## Loki on `partridge`

Loki runs in single-node filesystem mode on port `3100`, backed by a dedicated
`loki` disk mounted at `/var/lib/loki`. Grafana's provisioned Loki datasource
uses the same UID as the old Blink datasource, but now points at local Loki on
`127.0.0.1:3100`.

Loki is reverse-proxied for internal LAN log shipping at:

```text
https://loki.int.alcachofa.faith
```

Grafana Alloy clients should push logs to:

```text
https://loki.int.alcachofa.faith/loki/api/v1/push
```

After Terraform adds the disk, format it once before switching the NixOS config:

```sh
sudo mkfs.ext4 -F /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi5
```

After switching the host, verify Loki locally:

```sh
curl http://partridge:3100/ready
```

## Grafana on `partridge`

Grafana is served at:

```text
https://grafana.alcachofa.faith
```

Grafana uses the local PostgreSQL service for storage. Its Prometheus and Loki
datasources are provisioned with the same UIDs as Blink's old Grafana
datasources, so imported dashboards can keep their datasource references.
Prometheus and Loki both point at local Partridge services. Dashboards are
provisioned from the JSON files under `nixos/hosts/partridge/grafana/dashboards/`,
one folder each for Ops, Fitness, Music and Chatting, with UI edits disabled.
Change a dashboard by editing its JSON in the repo.

Grafana also has a provisioned `scheduler-postgres` datasource for Octopus
usage data in Partridge's local `scheduler` database. Apply the schema after
switching the host:

```sh
sudo -u postgres psql -d scheduler -f nixos/hosts/partridge/sql/scheduler-usages.sql
```

The scheduler writer password is generated on Partridge in the PostgreSQL state
directory:

```sh
sudo cat /var/lib/postgresql/scheduler-db-writer-password
```

Use that value as Blink scheduler's `DB_PASSWORD` when cutting scheduler over to
Partridge Postgres.

The helper script `scripts/export-grafana-dashboards.sh` exports dashboard,
folder, and datasource metadata from the old Grafana into the ignored
`grafana-dashboard-exports/` directory.

## Tailscale

`partridge` runs Tailscale for remote access over the tailnet. After the first
switch that enables it, authenticate the machine once:

```sh
sudo tailscale up
```

Partridge is the tailnet's subnet router: it advertises `10.4.0.0/23` so
tailnet devices away from home can reach the LAN, and it is an exit node. Both
take effect once approved in the tailnet policy. Falcon is a second exit node
and accepts Partridge's route.

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

The Cloudflare token is sops-encrypted in
`nixos/hosts/partridge/secrets/acme-cloudflare.yaml`, and sops-nix renders it
into the `acme-cloudflare.env` file the ACME module reads. The token needs Cloudflare `Zone:Read` and `DNS:Edit` permissions for the zone.
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
service backed by `/var/lib/postgresql`. Git over SSH uses Forgejo's built-in
SSH server on port 2222 as user `git`, for example
`ssh://git@code.alcachofa.faith:2222/<owner>/<repo>.git`. HTTPS remotes also
work.

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

`restic-backups-partridge-forgejo` backs `/srv/code/forgejo` up daily at 04:00
to the same B2 restic repository as the PostgreSQL backups, skipping logs,
temp files, queues, indexers, sessions and archive downloads. It stops Forgejo
for the length of the backup so repositories, LFS and refs are captured at
rest. It has no prune of its own: the `partridge-postgres` job's `forget`
applies its retention to these snapshots as well. A restore needs both the
matching Postgres dump and this snapshot.

```sh
sudo systemctl start restic-backups-partridge-forgejo.service
sudo restic-partridge-forgejo snapshots --path /srv/code/forgejo
```

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
the Vaultwarden personal vault from Bitwarden EU using the repo-packaged
`bitwarden-mirror` Go tool and the upstream `bw` CLI.

The refresh is intentionally destructive: it lists destination personal-vault
items and folders, permanently deletes items first and folders second, then
imports a fresh Bitwarden JSON export. The temporary plaintext export lives in
`/run/bitwarden-mirror` and is removed on success and failure.

Secrets are expected in `nixos/hosts/partridge/secrets/bitwarden-mirror.yaml`
as a sops-encrypted document with the keys shown in the adjacent `.example`
file, encrypted to the recipients in `.sops.yaml`.

## Building An Image Later

NixOS can build images from normal system configurations with:

```sh
nixos-rebuild build-image --image-variant proxmox --flake .#<host>
```

The flake does not expose any image outputs yet; add one alongside
`nixosConfigurations` when an image is needed.

`proxmox-vma` should be the native Proxmox backup/archive image format.
`proxmox-qcow-efi` is useful if importing a disk into an existing Terraform VM
is easier than restoring a VMA.

Run these from a machine with Nix installed. The Mac-side workspace has Nix
available, but Linux image builds still need to happen from the NixOS VM or
another Linux Nix builder.
