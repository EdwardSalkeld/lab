# Kite Media Migration Runbook

## Scope and Current State

`luna` is a standalone Proxmox host. `kite` is its installed NixOS media VM:

- root, Jellyfin, Navidrome, and Wantlist state disks are mounted by label;
- SSH and the QEMU guest agent are active;
- Jellyfin and Navidrome are intentionally inactive until their external media
  mounts exist.

The current recovery workload is Proxmox CT `57096` (`jellyfin-temp`) on
`sol`. It contains the temporary Jellyfin and Wantlist services. It is the
rollback artefact for this migration and must not be destroyed.

The physical disks to move are currently mounted on `sol`:

| Purpose | UUID | Current Sol mount |
| --- | --- | --- |
| Blink 4 TB SSD | `836b5915-74d0-4801-a2f3-aa32f54730db` | `/mnt/blink-ssd4tb` |
| Blink red HDD | `a1666c44-85b1-406a-8f25-8e1a67f8a4dc` | `/mnt/blink-redhdd` |

## Migration Steps

1. **Quiesce the Sol recovery workload.**
   Confirm Wantlist has no active import, then gracefully stop CT `57096`.
   Do not delete it or alter its bind-mount configuration. It has `onboot: 0`,
   so it will remain stopped. This prevents Jellyfin and Wantlist from writing
   while the source disks are moved.

2. **Move the physical disks from Sol to Luna.**
   Confirm CT `57096` is stopped, unmount the two host mounts on `sol`, then
   power down/disconnect the external disks and connect them to `luna`.
   The media service is unavailable from this point until Kite is working.

3. **Identify the disks on Luna before configuring access.**
   Match both filesystems against the UUIDs above and record their stable
   `/dev/disk/by-id` paths. Do not rely on `/dev/sdX` names or assume that
   existing filesystem labels are `media` and `music`.

4. **Pass the disks directly through to Kite and declare the real mounts.**
   The intended design is whole-disk USB passthrough to Kite, with stable
   Proxmox device selection. Update the Kite NixOS filesystem declarations to
   use the confirmed UUIDs. Initially expose the media views read-only to
   Jellyfin and Navidrome; retain a controlled writable path for Wantlist
   imports.

5. **Migrate and validate Jellyfin and Navidrome.**
   Copy Jellyfin state from the 4 TB SSD to Kite's dedicated Jellyfin state
   disk, then start the native NixOS services and verify the existing library
   paths, metadata, and Apple TV playback. The source state currently lives at
   `docker-volumes/docker_jfconfig` and `docker-volumes/docker_jfcache` on the
   4 TB SSD. Only one Jellyfin instance may use that recovered state at once.

6. **Move Wantlist to a Nix-managed service on Kite.**
   Implement its Nix packaging, secrets, persistent state at
   `/var/lib/wantlist`, and writable staging/import paths. Test the complete
   Transmission-to-import workflow against the passed-through media disks.

7. **Stabilize and retire the temporary service.**
   Leave CT `57096` stopped as the rollback artefact until Kite has operated
   successfully for an agreed period. A rollback requires stopping Kite,
   moving or reattaching the physical disks to Sol, restoring the Sol mounts,
   and starting CT `57096`; it is not safe to start the CT while the disks are
   attached to and in use by Kite.

## Guardrails

- External multi-terabyte disks are not Terraform-managed VM disks.
- Never use both the temporary CT and Kite against the recovered Jellyfin state
  at the same time.
- Keep media source libraries read-only for Jellyfin and Navidrome. Wantlist's
  writable import destination must be deliberate and tested separately.
- The existing Kite filesystem declarations contain placeholder external labels;
  replace them with the observed filesystem UUIDs before starting the services.
