# Blink NixOS Host

`blink` is the bare-metal server. The first NixOS adoption keeps Docker Compose
as the workload boundary, then leaves service-by-service conversion to later
work.

## Install Shape

Fresh install target:

- EFI filesystem mounted at `/boot/efi`, labelled `BOOT`
- root ext4 filesystem labelled `nixos`
- swap partition labelled `swap`

Existing data disks are declared by UUID and should not be reformatted:

- `/mnt/redhdd`
- `/mnt/ext2tb/1`
- `/mnt/ext2tb/3`
- `/mnt/ext2tb/4`
- `/mnt/ssd4tb`

## First Cutover

Before reinstalling, migrate kept Docker named volumes off the root disk:

```sh
sudo ./scripts/blink-migrate-docker-volumes.sh
```

The script copies kept volumes into:

```text
/mnt/ssd4tb/docker-volumes
```

The NixOS Compose units use override files that bind those migrated paths back
into the containers.

## Kept Compose Services

From `/home/edward/develop/house/blink/docker/docker-compose.yml`:

- `jellyfin`
- `cadvisor`
- `node_exporter`
- `reverse-proxy`
- `alloy`
- `pigallery2`
- `database`
- `navidrome`

The unit deliberately stops these old services if they are still running:

- `grafana`
- `prometheus`
- `loki`
- `promtail`
- `jogon`
- `bitwarden-backup`

From `/home/edward/develop/chatting/docker-compose.yml`:

- `bbmb`
- `handler`
- `worker`
- `site`

## Follow-Ups

- Retire the temporary MariaDB container.
- Convert Chatting from Docker to Nix-managed services with separate users.
- Move host-local secrets into `sops-nix`.
- Tighten firewall exposure if there is a concrete reason to do so.
