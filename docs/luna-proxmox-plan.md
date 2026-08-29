# Luna Proxmox Plan

## Summary

`luna` is the replacement mini PC ordered after Blink's boot SSD started
hanging firmware POST. The intended role is a second Proxmox host. The external
HDDs temporarily attached to `sol` for Jellyfin recovery will probably move to
`luna` once the host is installed and stable.

The first planned guest is `kite`, a NixOS VM for Jellyfin and Navidrome.

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
  Proxmox host 2
  kite
    NixOS VM
    Jellyfin
    Navidrome
    external media mounted read-only
```

## Repo State

Prepared in this branch:

- Terraform resource `proxmox_virtual_environment_vm.kite`
- Feature flag `enable_kite_vm`, defaulting to `false`
- NixOS host `.#nixosConfigurations.kite`
- NixOS check `.#checks.x86_64-linux.kite`

The Terraform resource is disabled by default because `luna` does not exist as
a Proxmox node yet. A normal Terraform plan should remain a no-op for Luna until
`enable_kite_vm = true` is set and the provider can reach the `luna` node.

## Install Plan

1. Install Proxmox VE on `luna`.
2. Give `luna` a stable LAN address and hostname.
3. Add the same Proxmox API access pattern used for `sol`, or otherwise make
   the existing Terraform provider able to create VMs on node `luna`.
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
8. Enable `kite` Terraform only after the host is ready:

   ```hcl
   enable_kite_vm = true
   ```

9. Apply Terraform to create the VM.
10. Install NixOS from the Proxmox console.
11. During install, label filesystems to match the checked-in hardware file:

   ```text
   /boot              BOOT
   /                  nixos
   /var/lib/jellyfin  jellyfin
   /var/lib/navidrome navidrome
   ```

12. Switch the VM to the repo config:

   ```sh
   nixos-rebuild switch --flake .#kite
   ```

## Media Disk Decision

This is deliberately not final yet. The right answer depends on what Luna sees
once the disks are attached.

Options:

- Pass whole USB disks through to `kite`.
- Mount disks on the Proxmox host and run media services in an LXC instead.
- Keep media services on a VM and use a host export, accepting the extra moving
  parts.

For Jellyfin, direct access to the media filesystem is simplest. If the Apple TV
is the only client and the server is LAN-only, operational simplicity matters
more than a perfect storage design.

## Migration From Temporary Jellyfin

Current temporary service:

- Host: `sol`
- CT: `57096`
- Address: `10.4.1.20`
- Jellyfin config: `/mnt/blink-ssd4tb/docker-volumes/docker_jfconfig`
- Jellyfin cache: `/mnt/blink-ssd4tb/docker-volumes/docker_jfcache`
- Media: `/mnt/blink-redhdd`
- Music: `/mnt/blink-ssd4tb/partial/record-library/library`

Before starting Jellyfin on `kite`, stop the temporary CT or at least stop
the Docker container inside it. Only one Jellyfin instance should use the
recovered config at a time.

Suggested migration flow:

```sh
pct exec 57096 -- docker stop jellyfin
rsync -aHAX --numeric-ids /mnt/blink-ssd4tb/docker-volumes/docker_jfconfig/ root@kite:/var/lib/jellyfin/
rsync -aHAX --numeric-ids /mnt/blink-ssd4tb/docker-volumes/docker_jfcache/ root@kite:/var/cache/jellyfin/
```

The exact paths may change once the final NixOS service layout is tested. Treat
this as the reminder to copy the state, not as the final cutover command.

## Open Questions

- What static IP should `luna` use?
- Should `kite` take over Blink's old `10.4.1.20`, or should that address
  stay reserved for a future revived Blink?
- Are the external media disks going to be passed through to the VM directly?
- Should Jellyfin stay native NixOS, or should it keep using the recovered
  Docker volume layout for a lower-risk first cutover?
- Should Navidrome share the same music tree at `/music`, or get a curated copy?
