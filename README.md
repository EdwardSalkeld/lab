## Home v2: Lab

Home infrastructure learning lab for Proxmox + NixOS.

Current managed paths:

- `partridge`: repo-managed NixOS VM
- `magpie`: disposable NixOS installer VM
- `wren`: disposable zero-touch Debian cloud-init VM for remote bring-up tests

`wren` is the current proving ground for remote-only VM creation: DHCP-backed
discovery, repo-managed SSH access, non-interactive Tailscale join, and a small
nginx hello page without needing a Proxmox console after Terraform apply.

Start here:

- `AGENTS.md` for current operational notes.
- `terraform/README.md` for Terraform commands.
- `nixos/README.md` for NixOS host configuration and deploy commands.
- `docs/wren-playbook.md` for the canonical `wren` teardown/recreate flow.
