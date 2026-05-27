## Lab Terraform Notes

This Terraform root manages NixOS VMs on Proxmox.

Active resources:

- `proxmox_virtual_environment_download_file.nixos_minimal_iso`
- `proxmox_virtual_environment_vm.nixos_01`
- `proxmox_virtual_environment_vm.partridge`

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

## Current VM

- Name: `nixos-01`
- VM ID: `59760`
- Node: `sol`
- ISO: `nixos-25.11-minimal-x86_64-linux.iso`
- Disk: 32 GiB on `local-lvm`
- Network bridge: `vmbr0`

The VM is intended to boot into the NixOS installer. Use the Proxmox console to
perform the first manual install.

## Repo-Managed VM

- Name: `partridge`
- Node: `sol`
- Root disk: 12 GiB on `local-lvm`
- Code disk: 5 GiB on `local-lvm`
- Network bridge: `vmbr0`

`partridge` is managed by the root Nix flake as `.#partridge`.
