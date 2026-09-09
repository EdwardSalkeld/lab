## Home v2: Lab

Home infrastructure learning lab for Proxmox + NixOS.

## Current Topology

Proxmox hosts:

- `sol`: primary Proxmox host
- `luna`: standalone Proxmox host

Repo-managed NixOS VMs:

- `partridge` on `sol`: monitoring, Grafana, Loki, and PostgreSQL
- `magpie` on `sol`: chatting services and Forgejo runner
- `kite` on `luna`: Jellyfin, Navidrome, and MCM

There is no standing disposable Debian cloud-image VM on `main` right now. The
July 2026 `wren` exercise was torn down completely; the next disposable VM
should be reintroduced in a dedicated branch rather than overload `magpie`
again.

Start here:

- `AGENTS.md` for current operational notes.
- `terraform/README.md` for Terraform commands.
- `nixos/README.md` for NixOS host configuration and deploy commands.
- `docs/wren-playbook.md` for the reusable pattern to recreate a disposable
  zero-touch Debian VM from scratch.
