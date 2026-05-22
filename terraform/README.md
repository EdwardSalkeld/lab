## Lab Terraform Notes

This Terraform root currently manages the first NixOS learning VM on Proxmox.

Active resources:

- `proxmox_virtual_environment_download_file.nixos_minimal_iso`
- `proxmox_virtual_environment_vm.nixos_01`

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
