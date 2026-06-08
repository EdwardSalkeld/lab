## Lab Terraform Notes

This Terraform root manages NixOS VMs on Proxmox.

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

## Repo-Managed VM

- Name: `partridge`
- Node: `sol`
- Root disk: 12 GiB on `local-lvm`
- Code disk: 5 GiB on `local-lvm`
- Postgres disk: 5 GiB on `local-lvm`
- Vaultwarden disk: 2 GiB on `local-lvm`
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
