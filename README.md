## Home v2: Lab

Home infrastructure learning lab for Proxmox + NixOS.

## Formatting

Run from the repository root with Nix, uv and Go installed:

```sh
nix run --no-update-lock-file --inputs-from . nixpkgs#nixfmt-tree
uvx --from ruff==0.17.5 ruff format .
gofmt -w tools
```

The independent CI checks use these commands:

```sh
nix run --no-update-lock-file --inputs-from . nixpkgs#nixfmt-tree -- --ci
uvx --from ruff==0.17.5 ruff format --check .
gofmt -d tools
test -z "$(gofmt -l tools)"
```

Nix formatting uses nixfmt through the standard nixfmt-tree wrapper, from the
repository's locked nixpkgs input. Ruff covers Python helpers and tests; gofmt
covers the Go helpers in `tools/`. CI uses the Go version in
`tools/bitwarden-mirror/go.mod`. Keep the Ruff version here, in the `Makefile`
and in `.github/workflows/format.yml` in sync. The existing Terraform formatting
check continues to run in the main CI workflow.

`make fmt` and `make fmt-check` run the same commands. `make test` runs
shellcheck and the script checks from CI, and `make build HOST=<host>` builds a
host's system closure.

## Current Topology

[AGENTS.md](AGENTS.md#hosts) has the per-host table of roles, Terraform
coverage and deploy paths.

Proxmox hosts on the home LAN (`10.4.1.0/24`), configured outside this repo:

- `sol`: primary Proxmox host
- `luna`: standalone Proxmox host

Luna's host-side, non-NixOS network recovery watchdog is maintained in
[`proxmox/luna/network-watchdog`](proxmox/luna/network-watchdog/). It is a
guarded manual install because the Proxmox host itself is Debian, not one of
this repository's NixOS configurations.

Repo-managed NixOS hosts:

- `partridge` on `sol`: Prometheus, Loki, Grafana, PostgreSQL, Forgejo,
  Vaultwarden and the Bitwarden mirror
- `magpie` on `sol`: chatting services and Forgejo runner
- `kite` on `luna`: Jellyfin, Navidrome, MPD, Photoview and MCM
- `falcon` on Hetzner Cloud: FreshRSS, plus public proxies for Kite's Navidrome
  and Chatting's webhooks on Magpie

Other machines:

- `fourth` on the home LAN: deploy orchestrator for CI, the host Terraform
  runs on, and the puller of Kite's local backup copy. It is not configured by
  this repo.

Tailscale joins them. `partridge` is the subnet router, advertising
`10.4.0.0/23` so tailnet devices away from home can reach the LAN, and both
`partridge` and `falcon` are exit nodes. Falcon is the one host outside the
house; fourth reaches it by its tailnet name.

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
