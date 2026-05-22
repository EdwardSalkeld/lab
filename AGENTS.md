# Lab Repo Guide

This repo is being rebuilt as a Proxmox + NixOS learning lab.

The old Talos Kubernetes/GitOps stack has been removed from the active
Terraform root. Some old modules and runbook files may remain temporarily as
reference material while the new lab takes shape.

## Current State

- Terraform Cloud workspace: `alcachofa/house`
- Active Terraform root: `terraform/`
- Proxmox node: `sol`
- First VM: `nixos-01`
- Current VM ID: `59760`
- Installer ISO: `nixos-25.11-minimal-x86_64-linux.iso`

The first stage is intentionally manual: Terraform creates a blank VM and
attaches the NixOS minimal ISO. NixOS should be installed from the Proxmox
console so the installation flow is visible and learnable.

## Terraform

Load Proxmox credentials from `terraform/.env` before running Terraform:

```sh
set -a
source terraform/.env
set +a
terraform -chdir=terraform plan
```

For this initial NixOS bootstrap stage only, `plan` and `apply` are allowed
without asking again. Do not treat that as blanket permission for later stages.

## First NixOS Install Notes

The VM boots from the NixOS minimal ISO first:

- VM name: `nixos-01`
- CPU: 2 cores
- Memory: 4 GiB
- Disk: 32 GiB on `local-lvm`
- Network: `vmbr0`
- Firmware: OVMF/UEFI

Use the Proxmox console for the first install. After installation, update
Terraform to boot from `scsi0` first or detach/empty the ISO.

Suggested early NixOS config goals:

- DHCP networking
- OpenSSH enabled
- Edward's public SSH keys installed
- qemu guest agent enabled after booting from disk

## Skills

The old `talos-upgrade` skill may still exist under `skills/`, but it is not
applicable to the current NixOS rebuild unless the Talos lab is restored.
