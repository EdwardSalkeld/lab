## Home v2: Lab

Home infrastructure learning lab for Proxmox + NixOS.

## Formatting

Run from the repository root with Nix, uv and Go installed:

```sh
nix run --no-update-lock-file --inputs-from . nixpkgs#nixfmt-tree
uvx --from ruff==0.17.2 ruff format .
gofmt -w tools
```

The independent CI checks use these commands:

```sh
nix run --no-update-lock-file --inputs-from . nixpkgs#nixfmt-tree -- --ci
uvx --from ruff==0.17.2 ruff format --check .
gofmt -d tools
test -z "$(gofmt -l tools)"
```

Nix formatting uses nixfmt through the standard nixfmt-tree wrapper, from the
repository's locked nixpkgs input. Ruff covers Python helpers and tests; gofmt
covers the Go helpers in `tools/`. CI uses the Go version in
`tools/bitwarden-mirror/go.mod`. Keep the Ruff version here and in
`.github/workflows/format.yml` in sync. The existing Terraform formatting check
continues to run in the main CI workflow.

## Current Topology

Proxmox hosts:

- `sol`: primary Proxmox host
- `luna`: standalone Proxmox host

Luna's host-side, non-NixOS network recovery watchdog is maintained in
[`proxmox/luna/network-watchdog`](proxmox/luna/network-watchdog/). It is a
guarded manual install because the Proxmox host itself is Debian, not one of
this repository's NixOS configurations.

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
- [Chatting on Lab](docs/chatting.md) for runtime upgrades, services, retention and webhook ingress.
- `scripts/magpie-codex-reauth.sh` to restore chatting's Codex login on magpie.
- `docs/wren-playbook.md` for the reusable pattern to recreate a disposable
  zero-touch Debian VM from scratch.
