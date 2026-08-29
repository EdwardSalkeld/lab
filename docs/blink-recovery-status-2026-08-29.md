# Blink Recovery Status - 2026-08-29

## Summary

The planned Blink NixOS reinstall is paused. The original Blink boot SSD causes
the machine firmware to hang during POST when attached. With that SSD removed,
the machine reaches BIOS and boots the NixOS installer USB normally, so the
problem currently appears isolated to the boot SSD or its direct connection.

The priority recovery action was to bring Jellyfin back for the Apple TV client
on the home LAN. Jellyfin is now running temporarily on `sol` in Proxmox CT
`57096`, using Blink's old LAN address `10.4.1.20`.

## Current Blink Hardware State

- Blink itself is not expected to return immediately.
- The original root/boot SSD should not be reused for a fresh install unless it
  can be proven healthy outside the machine.
- The NixOS installer USB boots when the suspect SSD is absent.
- The Blink data disks used for Jellyfin recovery are now attached to `sol`.

Known attached disks on `sol`:

| Purpose | Device seen on `sol` | UUID | Mount |
| --- | --- | --- | --- |
| Blink 4TB SSD | `/dev/sdb1` | `836b5915-74d0-4801-a2f3-aa32f54730db` | `/mnt/blink-ssd4tb` |
| Blink red HDD | `/dev/sdc1` | `a1666c44-85b1-406a-8f25-8e1a67f8a4dc` | `/mnt/blink-redhdd` |

`/mnt/blink-redhdd` is mounted read-only for Jellyfin media.

## Temporary Jellyfin Service

Jellyfin is running inside Proxmox CT `57096` on `sol`.

CT config at the time of recovery:

```text
arch: amd64
cores: 2
features: nesting=1,keyctl=1
hostname: jellyfin-temp
memory: 2048
mp0: /mnt/blink-ssd4tb/docker-volumes/docker_jfconfig,mp=/srv/jellyfin/config
mp1: /mnt/blink-ssd4tb/docker-volumes/docker_jfcache,mp=/srv/jellyfin/cache
mp2: /mnt/blink-redhdd,mp=/media,ro=1
mp3: /mnt/blink-ssd4tb/partial/record-library/library,mp=/music,ro=1
net0: name=eth0,bridge=vmbr0,gw=10.4.1.1,hwaddr=BC:24:11:1F:1C:05,ip=10.4.1.20/24,type=veth
onboot: 0
ostype: debian
rootfs: local-lvm:vm-57096-disk-0,size=8G
swap: 512
```

Inside the CT, Jellyfin is running as Docker container `jellyfin`:

```sh
docker run -d \
  --name jellyfin \
  --restart unless-stopped \
  --network host \
  -e JELLYFIN_PublishedServerUrl=http://home.alcachofa.uk/jellyfin \
  -v /srv/jellyfin/config:/config \
  -v /srv/jellyfin/cache:/cache \
  -v /media:/media:ro \
  -v /music:/music:ro \
  jellyfin/jellyfin:10.11.11
```

This is not a clean Jellyfin install. It uses the migrated Blink Jellyfin state:

- `/config` is `/mnt/blink-ssd4tb/docker-volumes/docker_jfconfig`
- `/cache` is `/mnt/blink-ssd4tb/docker-volumes/docker_jfcache`
- `/media` is `/mnt/blink-redhdd`
- `/music` is `/mnt/blink-ssd4tb/partial/record-library/library`

The recovered service has been verified:

- `http://10.4.1.20:8096/` returns `302 Location: web/`
- Docker reports the Jellyfin container as healthy
- Jellyfin logs show the existing database at `/config/data/jellyfin.db`
- Jellyfin logs show library watchers for `/media/film`, `/media/tv`,
  `/media/workspace`, and `/music`

## Operational Caveats

This setup is deliberately temporary:

- CT `57096` has `onboot: 0`.
- The `sol` disk mounts were created manually.
- If `sol` reboots, the mounts should be restored before starting CT `57096`.
- Only one Jellyfin instance may use the recovered config directory at a time.

Before bringing any future Blink-hosted Jellyfin back online, stop CT `57096` or
point the future service at a separate copy of the Jellyfin config.

## Useful Commands

Check the disk mounts on `sol`:

```sh
findmnt /mnt/blink-ssd4tb /mnt/blink-redhdd
```

Check the CT:

```sh
pct status 57096
pct config 57096
```

Check Jellyfin:

```sh
pct exec 57096 -- docker ps
pct exec 57096 -- docker logs --tail=80 jellyfin
curl -I http://10.4.1.20:8096/
```

If `sol` reboots, restore the current temporary shape with:

```sh
mkdir -p /mnt/blink-ssd4tb /mnt/blink-redhdd
mount UUID=836b5915-74d0-4801-a2f3-aa32f54730db /mnt/blink-ssd4tb
mount -o ro UUID=a1666c44-85b1-406a-8f25-8e1a67f8a4dc /mnt/blink-redhdd
pct start 57096
```

## If This Becomes Permanent

Recommended next work:

1. Make the `sol` mounts persistent by UUID with `nofail`.
2. Ensure CT `57096` starts only after those mountpoints are real mounts.
3. Rename the CT from `jellyfin-temp` to a stable name.
4. Decide whether to keep Docker-in-LXC or install Jellyfin directly in the CT.
5. Keep `10.4.1.20` if the Apple TV is already pinned to Blink's old address.
6. Move this from recovery notes into repo-managed host documentation or
   automation once the desired permanent host is decided.

## Related PRs

- PR 195: declarative Blink Wi-Fi with sops-nix.
- PR 196: explicit Blink ModemManager disable.

