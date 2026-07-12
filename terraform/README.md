## Lab Terraform Notes

This Terraform root manages VMs on Proxmox.

Active resources:

- `proxmox_virtual_environment_download_file.nixos_minimal_iso`
- `proxmox_virtual_environment_vm.partridge`
- `proxmox_virtual_environment_vm.magpie`

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

## Disposable Dev VM

- Name: `magpie`
- Node: `sol`
- Root disk: 12 GiB on `local-lvm`
- Network bridge: `vmbr0`

`magpie` is managed by the root Nix flake as `.#magpie`. It starts from the
same Proxmox VM shape as `partridge` but only has a root disk. The NixOS config
imports the shared Proxmox base module plus a disposable development-machine
module sized from Edward's dotfiles setup.

The QEMU guest agent is intentionally disabled while `magpie` is an ISO-booted
installer VM. Enabling it before NixOS is installed makes Proxmox/Terraform wait
on guest-agent reboot commands that cannot succeed yet. Enable it after the VM
has a real NixOS install with `qemu-guest-agent` running.

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
