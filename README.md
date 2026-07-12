## Home v2: Lab

Home infrastructure learning lab for Proxmox + NixOS.

Current managed paths:

- `partridge`: repo-managed NixOS VM
- `magpie`: disposable NixOS installer VM

There is no standing disposable Debian cloud-image VM on `main` right now. The
July 2026 `wren` exercise was torn down completely; the next disposable VM
should be reintroduced in a dedicated branch rather than left disabled on
`main`.

Start here:

- `AGENTS.md` for current operational notes.
- `terraform/README.md` for Terraform commands.
- `nixos/README.md` for NixOS host configuration and deploy commands.
- `docs/wren-playbook.md` for the reusable pattern to recreate a disposable
  zero-touch Debian VM from scratch.
