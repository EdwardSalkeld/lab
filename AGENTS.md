# Lab Repo Guide

This repo is a Proxmox + NixOS home lab: the NixOS hosts below, the Terraform
for the Proxmox VMs, and the CI that builds and deploys them.

## Hosts

The lab runs four NixOS hosts, all defined in the root flake's
`nixosConfigurations` and deployed the same way: on a push to `main`, CI builds
each host's closure, then asks fourth to switch every host to it (see
[docs/ci-built-nixos-deploy.md](docs/ci-built-nixos-deploy.md)). The
[Current Topology](README.md#current-topology) section of the README covers the
network side.

| Host | Runs on | Role and main services | Terraform | Deploy |
| --- | --- | --- | --- | --- |
| `partridge` | VM on `sol` | Monitoring (Prometheus, Loki, Grafana), PostgreSQL, Forgejo, Vaultwarden and the Bitwarden mirror, data jobs; Tailscale subnet router and exit node | Yes (`terraform/nixos-vm.tf`) | CI, via fourth |
| `magpie` | VM on `sol` | Chatting (BBMB, handler, worker) and the Forgejo Actions runner | Yes (`terraform/nixos-vm.tf`) | CI, via fourth |
| `kite` | VM on `luna` | Media: Jellyfin, Navidrome, MPD, Photoview, MCM; off-site restic backup of its data disk | Yes (`terraform/kite-vm.tf`), except its passed-through host disks and USB DAC | CI, via fourth |
| `falcon` | Hetzner Cloud | Public edge: FreshRSS, public proxies for Navidrome and Chatting webhooks; Tailscale exit node | No | CI, via fourth over Tailscale |

Machines this repo does not configure:

- `sol`: the primary Proxmox host (Debian).
- `luna`: a standalone Proxmox host (Debian). Its network watchdog lives in
  [`proxmox/luna/network-watchdog`](proxmox/luna/network-watchdog/) and is
  installed by hand.
- `fourth`: the deploy orchestrator. CI reaches it as `deploy@fourth` over
  Tailscale; it runs the `deploy/` scripts, Terraform plans and applies, and
  pulls Kite's local backup copy.

Terraform state is in the Terraform Cloud workspace `alcachofa/house`, and the
active root is `terraform/`. New Proxmox VMs start blank with the NixOS minimal
ISO attached and are installed with
[nixos/install-vm-runbook.md](nixos/install-vm-runbook.md); after that CI
deploys them like the others.

## Repo Rules

- Do not push to `main` unless the user explicitly asks for a direct push to
  `main`. Use a branch and PR for follow-up changes by default.

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
flake. Merging to `main` deploys it. For a manual switch from a checkout on a
host, run:

```sh
./scripts/nixos-switch.sh
```
