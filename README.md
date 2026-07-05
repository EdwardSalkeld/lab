## Home v2: Lab

Home infrastructure learning lab for Proxmox + NixOS.

Current first milestone:

- Terraform provisions one Proxmox VM, `nixos-01`.
- The VM boots from the NixOS 25.11 minimal ISO.
- NixOS installation is manual through the Proxmox console.

Current bootstrap experiment:

- Terraform can also provision a small zero-touch cloud-init VM, `wren`.
- `wren` is meant as a remote-management proving ground: no Proxmox console,
  repo-managed SSH access for Edward and Billy, and a basic nginx hello page.

Start here:

- `AGENTS.md` for current operational notes.
- `terraform/README.md` for Terraform commands.
- `nixos/README.md` for NixOS host configuration and deploy commands.
