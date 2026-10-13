## Lab Terraform Notes

This Terraform root manages VMs on Proxmox.

Active resources:

- `proxmox_virtual_environment_download_file.nixos_minimal_iso`
- `proxmox_virtual_environment_vm.partridge`
- `proxmox_virtual_environment_vm.magpie`
- `proxmox_virtual_environment_vm.kite` when `enable_kite_vm = true`

## Quick Ops

Load credentials:

```sh
set -a
source terraform/.env
set +a
```

Check the plan:

```sh
terraform -chdir=terraform plan
```

Apply the current stage:

```sh
terraform -chdir=terraform apply
```

Show VM outputs:

```sh
terraform -chdir=terraform output
```

There is no standing disposable Debian cloud-image VM on `main`. When the next
remote-only bootstrap exercise starts, add its Terraform resources in a branch
and use [../docs/wren-playbook.md](../docs/wren-playbook.md) as the reference
pattern.

## Repo-Managed VM

- Name: `partridge`
- Node: `sol`
- Root disk: 12 GiB on `local-lvm`
- Code disk: 5 GiB on `local-lvm`
- Postgres disk: 5 GiB on `local-lvm`
- Vaultwarden disk: 2 GiB on `local-lvm`
- Prometheus disk: 10 GiB on `local-lvm`
- Loki disk: 10 GiB on `local-lvm`
- Network bridge: `vmbr0`

`partridge` is managed by the root Nix flake as `.#partridge`.

## Chatting Host

- Name: `magpie`
- Node: `sol`
- Root disk: 36 GiB on `local-lvm`
- Workspace disk: 5 GiB on `local-lvm`
- Network bridge: `vmbr0`

`magpie` is managed by the root Nix flake as `.#magpie`. It is now the base
host target for moving `chatting` off Blink, so the VM shape includes a small
dedicated workspace disk mounted separately from the root filesystem when that
disk is present.

The QEMU guest agent is intentionally disabled while `magpie` is an ISO-booted
installer VM. Enabling it before NixOS is installed makes Proxmox/Terraform wait
on guest-agent reboot commands that cannot succeed yet. Enable it after the VM
has a real NixOS install with `qemu-guest-agent` running.

### Growing Magpie's root disk

The 36 GiB default increases the existing 24 GiB disk by 12 GiB. Check that
the `alcachofa/house` workspace does not override `magpie_root_disk_size`,
and review the Terraform plan for an in-place `scsi0` size change before
applying it. Sol's `local-lvm` thin pool had approximately 86 GiB physically
free when checked on 2026-10-13; check current capacity before applying.

Terraform only enlarges the virtual disk. The guest partition and ext4
filesystem must be grown separately by an operator with privileged guest
access. This change deliberately leaves guest resize settings unchanged;
it does not enable automatic partition or filesystem growth.

The current guest root is the final partition on the disk with serial
`magpie-root`: `/dev/sdb2`, labelled `nixos`, following the EFI partition.
After the operator completes the guest resize, verify the disk is 36 GiB,
the root filesystem is roughly 35.5 GiB, and chatting is healthy:

```sh
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS,SERIAL
df -h /
systemctl --failed
systemctl is-active chatting-handler.service chatting-worker.service
```

The host disk can also be enlarged directly on Sol with
`qm disk resize 75280 scsi0 36G`. This does not resize the guest filesystem
or require a guest reboot. Keep Terraform's desired size aligned with the
host to avoid drift. Guest resize is left to Edward; the Billy SSH key was
accepted on Magpie during the investigation, but interactive sudo required
a password and direct root SSH was rejected.

## Retired Chatting Test Container

Sparrow (CT 76300 on `sol`) was deleted on 2026-10-12 after testing finished.
Its Terraform resource and deployment installer have been removed. The plan
and apply scripts copy `deploy/sparrow-import.tf.template` into the Terraform
root to forget any remaining state without deleting the absent container again.
The template stays outside the Terraform root because tfsec cannot parse state
migration blocks. The historical filename is retained for compatibility with
dispatchers running older plan scripts; it now contains a retirement directive,
not an import. See [../docs/sparrow-chatting-test.md](../docs/sparrow-chatting-test.md).

## Kite VM

`luna` is planned as the second Proxmox host. The first planned guest is
`kite`, a NixOS VM for Jellyfin, Navidrome, and MCM.

The VM resource is enabled once Luna credentials are available:

```hcl
enable_kite_vm = true
```

After Proxmox is installed on `luna` and its API token exists, set
`LUNA_PROXMOXENDPOINT` and `LUNA_PROXMOXTOKEN` to create `kite` through the
standalone luna Proxmox API:

- root disk: 24 GiB
- Jellyfin metadata/cache disk: 32 GiB
- Navidrome metadata/cache disk: 8 GiB
- MCM app-state disk: 8 GiB
- CPU: 4 cores
- memory: 8192 MiB
- exposed service ports in the NixOS config: 4533, 8000, 8096

The guest config is exposed as `.#kite`. See
[../docs/luna-proxmox-plan.md](../docs/luna-proxmox-plan.md) before applying.
External multi-TB media disks stay outside Terraform-managed VM disks; they
should be mounted or passed through separately once the luna disk layout is
known.

## Disposable Debian VM Reference

The `wren` exercise established the current reference pattern for a disposable
remote-only Debian cloud-image VM:

- use Proxmox native cloud-init rather than snippet uploads
- keep the guest on DHCP
- use a minimal boot shape: imported `virtio0` root disk plus serial console
- treat boot-shape changes as replacement-only
- do direct guest SSH debugging once the machine is reachable

That flow is documented in [../docs/wren-playbook.md](../docs/wren-playbook.md)
and should be reapplied in a fresh branch when the next disposable VM is
introduced.
