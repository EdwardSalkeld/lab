# Lab Repo Guide

This repo is being rebuilt as a Proxmox + NixOS learning lab.

The old Talos Kubernetes/GitOps stack has been removed. This repo now focuses
on Proxmox-managed NixOS VMs.

## Current State

- Terraform Cloud workspace: `alcachofa/house`
- Active Terraform root: `terraform/`
- Proxmox node: `sol`
- Playground VM: `nixos-01`
- Repo-managed VM: `partridge`
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

## NixOS

NixOS host configuration lives under `nixos/` and is exposed through the root
flake. `partridge` can switch to the repo config from a checkout with:

```sh
./scripts/nixos-switch.sh
```
