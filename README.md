## Home v2: Lab

Home infrastructure learning lab, currently being rebuilt from a previous
Proxmox + Talos Kubernetes setup into a Proxmox + NixOS setup.

Current first milestone:

- Terraform provisions one Proxmox VM, `nixos-01`.
- The VM boots from the NixOS 25.11 minimal ISO.
- NixOS installation is manual through the Proxmox console.

Start here:

- `AGENTS.md` for current operational notes.
- `terraform/README.md` for Terraform commands.
