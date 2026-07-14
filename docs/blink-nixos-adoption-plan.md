# Blink NixOS Adoption Plan

Planning and decision log for the bare-metal `blink` adoption. Initial NixOS
implementation now lives under `nixos/hosts/blink/`.

`blink` is the current bare-metal server. The migration goal is to bring its
base OS, mounts, services, scheduled jobs, and Docker workloads under this repo
without losing the data currently living on attached disks.

## Current Host Snapshot

- Hostname: `blink`
- OS: Debian GNU/Linux 13 `trixie`
- Kernel: `6.12.85+deb13-amd64`
- Boot: UEFI, `/boot/efi` on `vfat`
- CPU: Intel Celeron N5105, 4 cores
- Memory: 15 GiB RAM, 975 MiB swap
- Primary network: Wi-Fi on `wlo1`, DHCP address `10.4.1.20/24`
- Wired NICs: `enp1s0` and `enp2s0`, both currently down
- Tailscale: enabled, address `100.86.181.28`, DNS handled by Tailscale
- Docker: active, with two compose projects in use

## Review Decisions

Reviewed so far:

| Item | Decision | Notes |
| --- | --- | --- |
| Docker/containerd | Keep | Keep for first NixOS cutover; possible later conversion away from Docker/Compose |
| Tailscale | Keep | Preserve remote access, DNS, and private identity |
| SSH | Keep | Required for administration |
| Wi-Fi on `wlo1` with NetworkManager | Keep | Stay on Wi-Fi for now |
| Wired NICs `enp1s0`, `enp2s0` | Leave unconfigured | Present but down; do not replace Wi-Fi yet |
| cloudflared | Drop | Forgotten/stale; do not migrate tunnel service |
| NFS server/RPC services | Keep | Preserve current LAN exports |
| smartmontools | Keep if easy | Include if straightforward in NixOS |
| MPD | Drop | Can be reintroduced later if needed |
| Avahi | Drop | No current need for mDNS discovery from this host |
| CUPS / cups-browsed | Drop | No printing role |
| Exim4 | Drop | No local MTA requirement |
| LightDM / XFCE desktop | Drop | Blink should become headless |
| ModemManager | Drop | No modem/mobile broadband role |
| Debian cron/anacron maintenance | Replace | Use NixOS-native timers/settings where relevant |
| `/mnt/ssd4tb` | Keep | Main app/data disk |
| `/mnt/ext2tb/1` | Keep | Jellyfin/media data |
| `/mnt/ext2tb/3` | Keep | Jellyfin/media data |
| `/mnt/ext2tb/4` | Keep | Jellyfin/media data and chatting workspace |
| `/mnt/redhdd` | Keep | Must add declarative mount; currently mounted but missing from `/etc/fstab` |
| NFS export `/mnt/ssd4tb/full/photos/inbox` | Keep | Preserve LAN write export |
| NFS export `/mnt/ssd4tb/full/apple` | Keep | Preserve LAN write export |
| NFS export `/media/inbox` | Keep | Preserve export; still verify backing path |
| Existing NFS export options | Keep initially | Preserve permissive LAN options for compatibility |
| Traefik reverse proxy | Keep | Blink still serves app routes |
| Grafana container | Drop | Retire Blink Grafana in favor of Partridge |
| Prometheus container | Drop | Retire Blink Prometheus in favor of Partridge |
| Loki container | Drop | Retire Blink Loki in favor of Partridge |
| Alloy | Keep | Reconfigure to ship to Partridge |
| Promtail | Drop | Alloy should replace it |
| Jellyfin | Keep | Preserve media service |
| Navidrome | Keep | Preserve music service |
| PiGallery2/photos | Keep | Preserve photo gallery |
| cAdvisor | Keep | Partridge Prometheus should scrape Blink Docker metrics |
| node_exporter | Keep | Partridge Prometheus should scrape Blink host metrics |
| MariaDB container | Keep temporarily | Preserve for cutover, but plan to remove soon |
| Jogon | Drop | Do not migrate |
| Bitwarden backup container | Drop | Replaced by Vaultwarden on Partridge |
| MariaDB exposed on `0.0.0.0:3306` | Keep temporarily | Revisit when MariaDB is removed |
| Docker named volumes | Migrate to persistent disk | Move/export kept app volumes before reinstall |
| Chatting stack | Keep | Keep all Chatting containers for cutover; later migrate Docker to Nix services with separate users |
| Developer/admin tools | Keep | Preserve common shell/admin workflow |
| Build/runtime tools | Keep for now | Can move to dev shells later |
| Network/debug tools | Keep | Useful for server operations |
| Media CLI tools for MPD | Drop | MPD is dropped |
| Firmware/microcode | Keep relevant firmware | Wi-Fi, Realtek NICs, and Intel microcode; SOF audio only if needed |
| Docker workload management | Keep Compose initially | Manage Compose with Nix/systemd first; convert later where useful |
| Docker volume target | `/mnt/ssd4tb/docker-volumes/...` | Use one persistent volume root for kept Docker state |
| Secrets approach | Host-local first, then sops-nix | Stabilize cutover with files outside git, then migrate to repo secrets |
| Install route | Open | Fresh reinstall remains the working default, but no strong preference yet |
| Root disk layout | Simple ext4 | EFI + ext4 root + swap, similar to current |
| User `edward` | Keep | Normal admin user with sudo and Docker access |
| Future Chatting service users | Later | Add when migrating Chatting from Docker to Nix services |
| SSH host keys | Preserve if easy | Not a blocker if they change |
| Tailscale machine identity | Preserve if easy | Not a blocker if it rejoins as a new device |
| SSH authentication | Prefer keys | Password login only for bootstrap/console convenience if needed |
| Traefik `80/443` | Keep exposed | Preserve current routing behavior |
| Traefik dashboard/API `8080` | Keep initially | Compatibility-first; can restrict later |
| MariaDB `3306` | Keep temporarily | Remove/restrict when MariaDB is retired |
| Direct app ports | Keep initially | Preserve existing LAN access |
| Metrics ports | Keep LAN-visible | LAN users seeing metrics is acceptable |
| Old Blink Grafana data | Leave/archive | Do not migrate service; keep data path initially |
| Old Prometheus volume | Archive if easy | Otherwise discard with dropped service |
| Old Loki volume | Archive if easy | Otherwise discard with dropped service |
| Existing Bitwarden backup output | Leave in place | Do not run backup container |
| Jogon config/data | Do not migrate | Leave source tree cleanup for later |
| Blink repo structure | Add `nixos/hosts/blink/` | Include `configuration.nix` and `hardware-configuration.nix` |
| Shared modules | Use selectively | Do not force Blink through Proxmox VM base module |
| First implementation branch/PR | Use branch and PR | No direct push to `main` |
| First boot target | Minimal reliable service set | SSH/Tailscale, mounts, Docker/Compose, then app stacks |
| Later cleanup target | Separate follow-ups | MariaDB removal, Chatting Nix services, sops-nix, firewall tightening |

## Filesystems And Data

Root disk:

| Device | Mount | Filesystem | Size | Notes |
| --- | --- | --- | --- | --- |
| `/dev/sda1` | `/boot/efi` | `vfat` | 512 MiB | UEFI system partition |
| `/dev/sda2` | `/` | `ext4` | 475.5 GiB | Debian root and home |
| `/dev/sda3` | swap | `swap` | 976 MiB | Current swap partition |

Data disks:

| Device | Mount | Filesystem | Size | Used | Notes |
| --- | --- | --- | --- | --- | --- |
| `/dev/sdb1` | `/mnt/redhdd` | `ext4` | 3.6 TiB | 2.6 TiB | Mounted, but not present in `/etc/fstab` output |
| `/dev/sdc1` | `/mnt/ext2tb/1` | `ext4` | 976.6 GiB | 98% | Jellyfin media |
| `/dev/sdc3` | `/mnt/ext2tb/3` | `ext4` | 488.3 GiB | 99% | Jellyfin media |
| `/dev/sdc4` | `/mnt/ext2tb/4` | `ext4` | 398.2 GiB | 19% | Jellyfin media and chatting workspace bind |
| `/dev/sdd1` | `/mnt/ssd4tb` | `ext4` | 3.6 TiB | 41% | Main app/data disk |

Current `/etc/fstab` declares root, EFI, swap, `/mnt/ext2tb/{1,3,4}`, and
`/mnt/ssd4tb`. It does not declare `/mnt/redhdd`; the NixOS config should add a
declarative mount for it.

Keep these host paths stable during migration unless deliberately changed:

- `/mnt/ssd4tb/full/database/mysql`
- `/mnt/ssd4tb/full/docker/grafana`
- `/mnt/ssd4tb/full/photos/archive`
- `/mnt/ssd4tb/full/photos/inbox`
- `/mnt/ssd4tb/full/apple`
- `/mnt/ssd4tb/full/bwexport`
- `/mnt/ssd4tb/partial/record-library/library`
- `/mnt/ext2tb/1`
- `/mnt/ext2tb/3`
- `/mnt/ext2tb/4`
- `/mnt/ext2tb/4/billy`
- `/mnt/redhdd`

## Running System Services

Services that look intentional and need an explicit keep/drop decision:

| Service | Current role | Initial migration stance |
| --- | --- | --- |
| `docker.service`, `containerd.service` | Main app runtime | Keep initially, possibly convert selected containers to native NixOS services later |
| `tailscaled.service` | Remote access and DNS | Keep |
| `ssh.service` | Remote administration | Keep |
| `NetworkManager.service` | Wi-Fi and network management | Keep unless switching to static/networkd |
| `nfs-server.service` and related RPC services | LAN file exports | Keep |
| `cloudflared.service` | Cloudflare tunnel | Drop |
| `mpd.service` | Music Player Daemon on port `6600` | Drop |
| `smartmontools.service` | Disk health monitoring | Keep if easy |
| `cron.service`, `anacron.service` | Debian scheduled maintenance | Replace with NixOS-native timers/settings where relevant |
| `cups.service`, `cups-browsed.service` | Printing | Drop |
| `avahi-daemon.service` | mDNS discovery | Drop |
| `exim4.service` | Local MTA on localhost port `25` | Drop |
| `lightdm.service`, desktop tasks | XFCE desktop stack | Drop; headless server |
| `ModemManager.service` | Modem/mobile broadband manager | Drop |
| `wpa_supplicant.service` | Wi-Fi support | Keep via NetworkManager/Wi-Fi setup |

Local custom unit files found:

- `/etc/systemd/system/cloudflared.service`
- `/etc/systemd/system/cloudflared-update.service`
- `/etc/systemd/system/cloudflared-update.timer`

The cloudflared service embeds a tunnel token in the unit. Since cloudflared is
now marked `Drop`, do not migrate the service or token. If cloudflared is ever
reintroduced, move the token into repo-managed secret handling or a host-local
secret file. The update timer file exists, but the active timer list did not
show it.

## Scheduled Jobs

User crontab:

- `edward` has no user crontab.

System cron:

- Standard Debian `/etc/crontab` runs hourly, daily, weekly, and monthly
  `run-parts`.
- `/etc/cron.d` contains Debian/anacron/e2scrub entries only.
- Active systemd timers are Debian maintenance timers: `apt-daily`,
  `apt-daily-upgrade`, `dpkg-db-backup`, `exim4-base`, `logrotate`, `man-db`,
  `e2scrub_all`, `fstrim`, `systemd-tmpfiles-clean`, and `anacron`.

Application scheduling appears to be inside containers rather than host cron.
The Bitwarden/KeePass backup container has `CRON_SCHEDULE`, defaulting to
`0 2 * * *`.

## Network Surface

Known intentional listeners:

| Port | Source | Notes |
| --- | --- | --- |
| `22` | SSH | Admin access |
| `80`, `443`, `8080` | Traefik | Reverse proxy and dashboard/API port |
| `111`, `2049`, dynamic RPC ports | NFS/rpcbind | LAN exports |
| `3000` | Grafana container | Also proxied by Traefik |
| `3100` | Loki container | Log storage API |
| `3101` | Alloy container | Alloy HTTP endpoint |
| `3306` | MariaDB container | Keep temporarily; revisit when MariaDB is removed |
| `3456` | PiGallery2 container | Photos |
| `4533` | Navidrome container | Music |
| `6600` | MPD | Drop unless reintroduced later |
| `8083` | cAdvisor container | Metrics |
| `8096` | Jellyfin container | Media |
| `9090` | Prometheus container | Metrics |
| `9100` | node_exporter container | Host metrics |
| `9464`, `9465`, `9466` | Chatting stack | Handler, worker, site |
| `9876`, `9877` | Chatting BBMB | App and metrics/health |

NixOS firewall rules should be explicit. Initial posture is compatibility-first:
preserve existing LAN-visible app and metrics ports, then tighten later only
where there is a clear reason.

## File Sharing

Current NFS exports:

| Export | Clients | Options |
| --- | --- | --- |
| `/media/inbox` | `10.4.1.0/24` | `rw`, `all_squash`, `anonuid=1000`, `anongid=1000`, `insecure` |
| `/mnt/ssd4tb/full/photos/inbox` | `10.4.1.0/24` | Same options |
| `/mnt/ssd4tb/full/apple` | `10.4.1.0/24` | Same options |

`/media/inbox` is a symlink to
`/mnt/ssd4tb/partial/record-library/inbox`; the NixOS config should recreate
that symlink before exporting it.

No Samba config files were found in the first pass.

## Docker Workloads

Primary compose source:

- `/home/edward/develop/house/blink/docker/docker-compose.yml`

Services:

| Service/container | Image | Data/config mounts | Initial migration stance |
| --- | --- | --- | --- |
| `jellyfin` | `jellyfin/jellyfin` | Docker volumes `jfconfig`, `jfcache`; media binds from `/mnt/ext2tb/*` and music library | Keep |
| `grafana` | `grafana/grafana-oss` | `/mnt/ssd4tb/full/docker/grafana` | Drop; Partridge is the Grafana host |
| `prometheus` | `prom/prometheus` | Docker volume `prometheus-storage`; config under `house/blink/configs` | Drop; Partridge is the Prometheus host |
| `cadvisor` | `gcr.io/cadvisor/cadvisor` | Host filesystem and Docker binds | Keep; Partridge should scrape Blink Docker metrics |
| `node_exporter` | `quay.io/prometheus/node-exporter` | Host root bind, host network | Keep; Partridge should scrape Blink host metrics |
| `reverse-proxy` | `traefik:v3.6.7` | `traefik.conf`, `acme.json`, Cloudflare token file, Docker socket | Keep |
| `loki` | `grafana/loki:3.3.1` | Docker volume `loki-storage`; config under `house/blink/docker` | Drop; Partridge is the Loki host |
| `alloy` | `grafana/alloy` | config under `house/blink/docker`; host logs/run binds | Keep; point at Partridge |
| `promtail` | `grafana/promtail:2.9.13` | Docker logs and socket binds | Drop; replaced by Alloy |
| `pigallery2` / `photos` | `bpatrik/pigallery2` | config/tmp under compose tree; DB volume; photos archive bind | Keep |
| `database` | `mariadb:11` | `/mnt/ssd4tb/full/database/mysql`; log volume | Keep temporarily; expected to be removed soon |
| `jogon` | `ghcr.io/brokensbone/jog-on-backend:main` | secret config file under compose tree | Drop |
| `bitwarden-backup` | local build from `../bwexport` | `/mnt/ssd4tb/full/bwexport`; logs under compose tree | Drop; replaced by Vaultwarden on Partridge |
| `navidrome` | `deluan/navidrome` | `/home/edward/develop/house/blink/navidrome`; music library bind | Keep |

Chatting compose source:

- `/home/edward/develop/chatting/docker-compose.yml`

Services:

| Service/container | Image/build | Data/config mounts | Initial migration stance |
| --- | --- | --- | --- |
| `chatting-bbmb-1` | local build `Dockerfile.bbmb` | no persistent mount found | Keep |
| `chatting-handler-1` | `ghcr.io/edwardsalkeld/chatting:latest` | handler config bind, data/temp/GitHub auth volumes | Keep |
| `chatting-worker-1` | `ghcr.io/edwardsalkeld/chatting:latest` | worker config bind, auth volumes, workspace bind `/mnt/ext2tb/4/billy` | Keep |
| `chatting-site-1` | `node:22-alpine` | generated site volume | Keep |

All Chatting services are marked `Keep` for the initial cutover. Longer term,
the desired direction is to migrate them from Docker to Nix-managed services
running as separate service users.

Other compose candidates found under `~/develop` may be old copies or for other
hosts:

- `/home/edward/develop/house-scheduler-postgres/blink/...`
- `/home/edward/develop/house/{falcon,fourth,study}/...`
- `/home/edward/develop/webstack/archive/...`

Do not migrate these without a separate review.

## Secrets And State Risks

- The Blink Docker compose tree contains plaintext secrets and secret file
  references. Do not transcribe secret values into Nix files.
- The cloudflared systemd unit contains a tunnel token. Since cloudflared is
  dropped, do not migrate the unit or token.
- Docker named volumes contain important state and must be moved/exported before
  reinstall. Kept app volumes should be migrated onto a persistent disk path,
  likely under `/mnt/ssd4tb`, rather than left under `/var/lib/docker` on the
  root disk:
  - `docker_pigallery2-storage`
  - `docker_jfconfig`
  - `docker_jfcache`
  - `chatting_handler-data`
  - `chatting_worker-data`
  - `chatting_html-output`
  - `chatting_codex-auth`
  - `chatting_claude-auth`
  - `chatting_gh-auth`
- Dropped observability volumes can be archived first if easy; otherwise they
  can be discarded with the dropped services:
  - `docker_prometheus-storage`
  - `docker_loki-storage`
- Existing Grafana data at `/mnt/ssd4tb/full/docker/grafana` can be left in
  place even though the Blink Grafana service is not migrated.
- Existing Bitwarden backup output at `/mnt/ssd4tb/full/bwexport` can be left in
  place even though the backup container is not migrated.

## Package Inventory To Account For

Likely keep as system packages or service dependencies:

- `docker-ce`, `docker-compose-plugin`, `containerd.io`
- `tailscale`
- `openssh-client`, SSH server task
- `nfs-kernel-server`
- `smartmontools`
- `restic`, `rsync`
- `git`, `vim`, `tmux`, `screen`, `ripgrep`, `fzf`
- `golang`, `nodejs`, `build-essential`, `cmake`, `ninja-build` for now
- `mariadb-client`, `sqlite3`
- `bind9-dnsutils`, `nmap`, `tcpdump`, `traceroute`, `netcat-traditional`
- firmware: `firmware-iwlwifi`, `firmware-realtek`, `firmware-misc-nonfree`,
  `intel-microcode`

Likely review/drop for a headless server:

- `task-xfce-desktop`, `task-desktop`, `lightdm`
- `cups`, `cups-browsed`
- `ModemManager`
- `exim4`
- `lightdm`, XFCE, and desktop task packages
- `mpd`, `mpc`, `ncmpcpp`
- `cloudflared`
- `firmware-sof-signed` unless audio support is needed later
- `reportbug`, `debian-faq`, desktop/localization extras

## Proposed Repo Shape

Implemented initial shape:

- Added a new `nixosConfigurations.blink` flake target.
- Added `nixos/hosts/blink/configuration.nix`.
- Added `nixos/hosts/blink/hardware-configuration.nix`.
- Kept bare-metal-specific config separate from Proxmox VM modules.
- Prefer explicit bind-mounted data paths under `/mnt/ssd4tb/docker-volumes/...`
  over opaque Docker named volumes for future recoverability.

## Migration Worklist

1. Decide install route.
   - Option A: fresh NixOS reinstall on `/dev/sda`, preserving external data
     disks.
   - Option B: `nixos-infect` style conversion, with a full rollback/backup plan.
   - Fresh reinstall remains the working default, but the route is not decided.

2. Decide what to keep, drop, or move.
   - Keep the reviewed decisions above as the migration contract.
   - Drop Blink Grafana, Prometheus, Loki, Promtail, Jogon, Bitwarden backup,
     cloudflared, MPD, Avahi, CUPS, Exim4, ModemManager, and desktop services.

3. Back up before touching the OS.
   - Backup `/home/edward/develop/house/blink`.
   - Backup `/home/edward/develop/chatting`.
   - Backup `/etc/fstab`, `/etc/exports`, NetworkManager connection profiles,
     SSH host keys, and Tailscale state if preserving identity.
   - Move/export required Docker named volumes onto persistent disk paths.
   - Snapshot or external-backup `/mnt/ssd4tb` and the media disks where practical.

4. Model hardware and filesystems.
   - Declare UEFI boot.
   - Declare simple EFI + ext4 root + swap strategy.
   - Declare persistent mounts by UUID or `/dev/disk/by-id`.
   - Add `/mnt/redhdd` as a declarative mount.
   - Ensure mount ordering before Docker/app services start.

5. Model networking.
   - Declare hostname `blink`.
   - Enable NetworkManager and Wi-Fi firmware.
   - Preserve Tailscale and DNS behavior.
   - Leave wired NICs unconfigured for now.
   - Define firewall rules explicitly.

6. Model core services.
   - OpenSSH.
   - Tailscale.
   - Docker.
   - smartmontools.
   - NFS exports.
   - Do not migrate cloudflared.
   - Do not migrate MPD.

7. Model Docker workloads.
   - Start with compose files as source of truth, managed by Nix/systemd.
   - Preserve container names where external routes or dashboards depend on
     them.
   - Preserve all bind mounts and replace required named volumes with persistent
     disk paths where practical.
   - Keep secrets as host-local files for initial cutover, then migrate to
     `sops-nix`.

8. Validate on a dry target before reinstall where possible.
   - Build `.#nixosConfigurations.blink.config.system.build.toplevel`.
   - Lint/evaluate all modules.
   - Compare generated firewall ports to current listeners.
   - Confirm every declared mount has a real disk.

9. Cut over.
   - Stop Docker workloads cleanly.
   - Take final volume/data backup.
   - Reinstall or infect.
   - Boot to minimal network plus SSH/Tailscale first.
   - Mount data disks.
   - Start Docker and core services.
   - Bring app stacks up one group at a time.

10. Post-cutover checks.
    - SSH over LAN and Tailscale.
    - DNS resolution through Tailscale.
    - NFS exports reachable from a LAN client.
    - Traefik routes and TLS renewal.
    - Alloy ships to Partridge.
    - Jellyfin, Navidrome, PiGallery2.
    - MariaDB integrity and dependent apps.
    - SMART monitoring sees all disks.

## Open Questions

- Confirm the final install route: fresh reinstall versus `nixos-infect`.
- Confirm exact destination paths under `/mnt/ssd4tb/docker-volumes/...` for
  each kept Docker named volume.
- Confirm whether old Prometheus and Loki volumes should be archived before
  dropping those services.
