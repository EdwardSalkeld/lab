## Lab Terraform Notes

This Terraform root manages VMs on Proxmox.

Active resources:

- `proxmox_virtual_environment_download_file.nixos_minimal_iso`
- `proxmox_virtual_environment_download_file.debian_12_genericcloud`
- `proxmox_virtual_environment_file.hello_user_data_cloud_config`
- `proxmox_virtual_environment_vm.partridge`
- `proxmox_virtual_environment_vm.magpie`
- `proxmox_virtual_environment_vm.hello`

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

## Zero-Touch Hello VM

- Name: `wren`
- Node: `sol`
- Root disk: 12 GiB on `local-lvm`
- Memory: 2048 MiB
- Network bridge: `vmbr0`

`wren` uses the official Debian 12 generic cloud image plus a cloud-init
configuration generated natively by Proxmox. The current bootstrap path:

- creates a `billy` SSH user and authorizes both Billy and Edward's repo-managed
  keys on that account
- uses DHCP on `vmbr0`
- avoids Proxmox snippet uploads and any Terraform-time root SSH into the
  Proxmox host

This is intentionally narrower than the first merged attempt. The earlier
snippet-based approach also tried to install `qemu-guest-agent`, install
`nginx`, and write the hello page during first boot, but that path depended on
Proxmox `Snippets` support on `local` plus root-authorized SSH from the deploy
environment into the Proxmox host. The current config removes those
prerequisites so Terraform apply can succeed on the existing setup.
