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

## Deployment Plan

1. Review and merge the branch or PR that adds `.#blink`.

2. While still on Debian, migrate kept Docker named volumes:

   ```sh
   sudo ./scripts/blink-migrate-docker-volumes.sh
   ```

   Spot-check that the copied data exists under:

   ```text
   /mnt/ssd4tb/docker-volumes
   ```

3. Take final backups before changing the OS:

   ```text
   /home/edward/develop/house/blink
   /home/edward/develop/untitled-music-project
   /home/edward/.config/beets
   /home/edward/.ssh/ucc
   /etc/fstab
   /etc/exports
   /etc/NetworkManager/system-connections
   /etc/ssh
   /var/lib/tailscale
   /mnt/ssd4tb/docker-volumes
   ```

   Keep the existing data disks attached and do not reformat them:

   ```text
   /mnt/ssd4tb
   /mnt/ext2tb/1
   /mnt/ext2tb/3
   /mnt/ext2tb/4
   /mnt/redhdd
   ```

4. Install NixOS on the root disk only. Label the new filesystems:

   ```text
   root ext4: nixos
   EFI vfat:  BOOT
   swap:      swap
   ```

5. Boot the new install, get Wi-Fi/networking working, clone this repo, and use
   the branch or `main` revision containing `.#blink`.

   Preserving SSH host keys and Tailscale machine identity is useful but not a
   blocker. If restoration is awkward, accept new SSH host keys and rejoin
   Tailscale as a new device.

6. Switch to the repo config:

   ```sh
   sudo nixos-rebuild switch --flake .#blink
   ```

7. Verify base services and mounts:

   ```sh
   systemctl status docker
   systemctl status blink-house-compose
   systemctl status blink-wantlist-compose
   findmnt /mnt/ssd4tb /mnt/redhdd /mnt/ext2tb/1 /mnt/ext2tb/3 /mnt/ext2tb/4
   exportfs -v
   docker ps
   ```

8. Check the kept service ports:

   ```text
   Traefik: 80, 443, 8080
   Jellyfin: 8096
   Navidrome: 4533
   PiGallery2: 3456
   MariaDB: 3306
   cAdvisor: 8083
   node_exporter: 9100
   Alloy: 3101, shipping to Partridge Loki
   Wantlist: https://wantlist.b.alcachofa.faith/
   ```

9. Confirm the dropped services stay stopped or absent:

   ```text
   cloudflared
   mpd
   avahi
   cups
   exim4
   lightdm/XFCE
   ModemManager
   Blink grafana/prometheus/loki/promtail
   jogon
   bitwarden-backup
   ```

10. Leave cleanup for separate follow-up work:

    ```text
    retire MariaDB
    move host-local secrets to sops-nix
    archive or delete old Prometheus/Loki volumes
    tighten firewall only if a concrete need appears
    ```

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

From `/home/edward/develop/untitled-music-project/deploy/prod/docker-compose.yml`:

- `api`
- `worker`

Wantlist depends on host-local state restored before the Compose unit is
started: the checkout (including deploy/prod/.env), /home/edward/.config/beets,
and /home/edward/.ssh/ucc. Its media, inbox, TV, film, and workspace paths are
already on the retained data disks.

## Follow-Ups

- Retire the temporary MariaDB container.
- Move host-local secrets into `sops-nix`.
- Tighten firewall exposure if there is a concrete reason to do so.
