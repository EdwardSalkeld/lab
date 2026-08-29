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
- Root disk: 24 GiB on `local-lvm`
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

## Kite VM

`luna` is planned as the second Proxmox host. The first planned guest is
`kite`, a NixOS VM for Jellyfin, Navidrome, and Wantlist.

The VM resource is disabled by default:

```hcl
enable_kite_vm = false
```

After Proxmox is installed on `luna` and its API token exists, set
`LUNA_PROXMOXENDPOINT`, `LUNA_PROXMOXTOKEN`, and `enable_kite_vm = true` to
create `kite` through the standalone luna Proxmox API:

- VM disk: 64 GiB root disk for the OS and service metadata
- CPU: 4 cores
- memory: 8192 MiB
- exposed service ports in the NixOS config: 4533, 8000, 8096

The guest config is exposed as `.#kite`. See
[../docs/luna-proxmox-plan.md](../docs/luna-proxmox-plan.md) before enabling
the VM. External multi-TB media disks stay outside Terraform-managed VM disks;
they should be mounted or passed through separately once the luna disk layout is
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
