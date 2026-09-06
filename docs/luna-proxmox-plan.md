# Luna Proxmox Plan

## Summary

`luna` is the replacement mini PC ordered after Blink's boot SSD started
hanging firmware POST. The intended role is a second, standalone Proxmox host,
not a member of a Proxmox cluster with `sol`. The external HDDs temporarily
attached to `sol` for Jellyfin recovery will probably move to `luna` once the
host is installed and stable.

The first planned guest is `kite`, a NixOS VM for Jellyfin, Navidrome, and
Wantlist.

## Current Deployment (2026-09-06)

`luna` is now an independent Proxmox VE host at `10.4.1.33`; it is not a
cluster member of `sol`. `kite` is running at `10.4.1.82` with four cores and
8 GiB RAM. Terraform owns its root and application-state disks:

| Guest disk | Purpose | Size |
| --- | --- | --- |
| `scsi0` | NixOS root | 24 GiB |
| `scsi1` | Jellyfin state and cache | 32 GiB |
| `scsi2` | Navidrome state | 8 GiB |
| `scsi3` | Reserved Wantlist state | 8 GiB |

The two multi-terabyte disks are intentionally **not** Terraform resources.
They are raw host-device attachments on Luna, excluded from Proxmox backups:

| Guest disk | Luna device | Filesystem UUID | Kite mount | Access |
| --- | --- | --- | --- | --- |
| `scsi4` | `/dev/disk/by-id/wwn-0x50014ee21389c2e6` | `836b5915-74d0-4801-a2f3-aa32f54730db` | `/data` | read-only |
| `scsi5` | `/dev/disk/by-uuid/a1666c44-85b1-406a-8f25-8e1a67f8a4dc` | `a1666c44-85b1-406a-8f25-8e1a67f8a4dc` | `/media` | read-only |

The `scsi5` attachment uses its UUID rather than the original USB `by-id`
name because that name contains a colon, which the Proxmox Terraform provider
cannot parse. Terraform plans must remain no-ops with these raw attachments in
place; do not model multi-TB media as Terraform VM disks.

Kite's NixOS configuration mounts the state disks and both physical disks at
boot. Jellyfin uses `/media` only, with a dedicated cache bind-mounted from
its state disk. Navidrome uses only
`/data/partial/record-library/library`; it must not scan all of `/data`.
Jellyfin has been removed from the former music library through its UI.

The migrated Jellyfin and Navidrome state is live and both services have
survived a cold reboot. The temporary recovery CT on Sol (`57096`) remains
stopped as a rollback reference. Wantlist has not yet moved to Kite.

## Hardware Assumption

Ordered class:

- HP ProDesk 600 G4 Mini
- Intel Core i5-8500T
- 16 GB RAM
- 256 GB SSD

This is an 8th-generation Intel, 6-core machine. It is a better compute target
than `sol` for small service VMs, but it is still a mini PC rather than a NAS.
Expect limited internal storage expansion; the bulk media disks remain external.

## Target Shape

```text
sol
  Proxmox host 1
  current temporary Jellyfin CT 57096
  partridge
  magpie

luna
  standalone Proxmox host 2
  kite
    NixOS VM
    Jellyfin
    Navidrome
    Wantlist
    external media mounted read-only for Jellyfin/Navidrome
    external media mounted writable for Wantlist imports
```

## Repo State

Prepared in this branch:

- Terraform resource `proxmox_virtual_environment_vm.kite`
- Terraform provider alias `proxmox.luna`
- Luna-local NixOS ISO download resource
- Feature flag `enable_kite_vm`, defaulting to `true`
- NixOS host `.#nixosConfigurations.kite`
- NixOS check `.#checks.x86_64-linux.kite`

The Terraform resources are enabled now that `luna` exists. Before deploying,
configure `LUNA_PROXMOXENDPOINT` and `LUNA_PROXMOXTOKEN` so Terraform talks
directly to the standalone luna Proxmox API rather than trying to reach a node
named `luna` through `sol`.

## Install Plan

1. Install Proxmox VE on `luna`.
2. Give `luna` a stable LAN address and hostname.
3. Add the same Proxmox API access pattern used for `sol`, but as separate
   `LUNA_PROXMOXENDPOINT` and `LUNA_PROXMOXTOKEN` Terraform variables.
4. Confirm basic host state:

   ```sh
   pveversion
   pvesh get /nodes
   pvesm status
   ip addr
   ```

5. Attach the external media disks to `luna`.
6. Identify disk UUIDs and stable by-id names:

   ```sh
   lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,MODEL,SERIAL
   find /dev/disk/by-id -maxdepth 1 -type l -ls
   ```

7. Decide whether the external disks are passed through to the VM or mounted on
   the Proxmox host and exposed through a different mechanism.
8. Confirm `kite` Terraform is enabled:

   ```hcl
   LUNA_PROXMOXENDPOINT = "https://luna:8006/"
   enable_kite_vm = true
   ```

9. Apply Terraform to create the VM.
10. Install NixOS from the Proxmox console.
11. During install, label VM filesystems to match the checked-in hardware file:

   ```text
   /boot              BOOT
   /                  nixos
   /var/lib/jellyfin  jellyfin
   /var/lib/navidrome navidrome
   /var/lib/wantlist  wantlist
   ```

12. Switch the VM to the repo config:

   ```sh
   nixos-rebuild switch --flake .#kite
   ```

## Media Disk Decision

The first-cut decision is whole-disk passthrough to Kite. This keeps the media
services simple and isolates all filesystem access in the guest.

Jellyfin and Navidrome receive read-only mounts. When Wantlist moves, it needs
a narrowly scoped writable import and destination design; do not make these
service mounts broadly writable as a shortcut. These are multi-TB external
disks, so Terraform must not model them as Proxmox VM disks.

## Migration From Temporary Jellyfin

Former temporary service:

- Host: `sol`
- CT: `57096`
- Address: `10.4.1.20`
- Jellyfin config: `/mnt/blink-ssd4tb/docker-volumes/docker_jfconfig`
- Jellyfin cache: `/mnt/blink-ssd4tb/docker-volumes/docker_jfcache`
- Media: `/mnt/blink-redhdd`
- Music: `/mnt/blink-ssd4tb/partial/record-library/library`

The CT was stopped before Jellyfin started on Kite. Keep it stopped: only one
Jellyfin instance may use the recovered config at a time.

Suggested migration flow:

```sh
pct exec 57096 -- docker stop jellyfin
rsync -aHAX --numeric-ids /mnt/blink-ssd4tb/docker-volumes/docker_jfconfig/ root@kite:/var/lib/jellyfin/
rsync -aHAX --numeric-ids /mnt/blink-ssd4tb/docker-volumes/docker_jfcache/ root@kite:/var/cache/jellyfin/
```

The exact paths may change once the final NixOS service layout is tested. Treat
this as the reminder to copy the state, not as the final cutover command.

## Wantlist On Kite

Wantlist should move to `kite` with Jellyfin and Navidrome. The temporary
recovery service is Docker Compose in CT `57096`, but the preferred permanent
shape under NixOS is native systemd services rather than Docker:

- `wantlist-migrate.service`: one-shot Alembic migration before app startup.
- `wantlist-api.service`: FastAPI/Uvicorn API serving the SPA on port 8000.
- `wantlist-worker.service`: scheduler/import worker.
- `wantlist.target`: groups the migration, API, and worker.

Likely Nix inputs and packaging work:

- Add `untitled-music-project` or a renamed Wantlist repo as a flake input.
- Build the backend with `uv2nix`, `pyproject.nix`, or a local Python
  application derivation.
- Build the frontend with the repo's `package-lock.json`, then provide the
  built SPA directory to the API through `WANTLIST_STATIC_DIR`.
- Keep the Postgres database on `partridge` unless there is a later reason to
  move it.

Runtime state and paths:

- Beets config/library root: `/mnt/ssd4tb/partial/record-library`
- Music library: `/mnt/ssd4tb/partial/record-library/library`
- Import inbox/staging: keep on the writable destination media disk, for
  example `/mnt/redhdd/workspace/wantlist-stage`
- Watch directory: `/mnt/ssd4tb/partial/record-library/inbox`
- TV root: `/mnt/redhdd/tv`
- Film root: `/mnt/redhdd/film`
- Workspace root: `/mnt/redhdd/workspace`

Secrets should not remain in a copied `.env` file once Wantlist is Nix-managed.
Move these into `sops-nix` for `kite`:

- `WANTLIST_DATABASE_URL`
- Spotify client ID/secret/redirect URI
- Transmission RPC URL/user/password
- Transmission SSH host/user/key path
- Optional notification webhook

The UCC/seedbox SSH private key should become a managed secret file with tight
permissions, mounted or written at a stable path used by
`WANTLIST_TRANSMISSION_SSH_KEY`.

Open implementation questions:

- Whether to keep the API on plain LAN HTTP port 8000 or put it behind a
  Traefik/Caddy route on `kite`.
- Whether Wantlist should run as root for media imports, or as a dedicated user
  with group write access to the media directories.
- Whether torrent import destinations should be writable inside the VM via disk
  passthrough, a host bind/LXC-style design, or a network filesystem.
- Whether the app source repo should keep the current name or be renamed before
  becoming a long-lived flake input.

## Open Questions

- Whether Wantlist should stay on LAN-only HTTP, or move behind a TLS route on
  Kite.
- The least-privilege writable media path for Wantlist imports and final
  destinations.
