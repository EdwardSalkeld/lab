## NixOS Configurations

This directory is the start of the repo-owned NixOS configuration.

Current targets:

- `partridge`: the first repo-managed NixOS VM.

## Installing Packages

On the current manually installed VM, the immediate path is to edit
`/etc/nixos/configuration.nix` and run:

```sh
sudo nixos-rebuild switch
```

For a permanent system package, add it to `environment.systemPackages` in
the system configuration:

```nix
environment.systemPackages = with pkgs; [
  git
  htop
  vim
];
```

After a host is adopted into this repo, add shared packages to
`nixos/modules/proxmox-vm-base.nix`, then rebuild the host. For `partridge`:

```sh
sudo nixos-rebuild switch --flake .#partridge
```

For a temporary shell with a package:

```sh
nix shell nixpkgs#htop
```

For a user-profile package that is not part of the system config:

```sh
nix profile install nixpkgs#htop
```

Prefer `environment.systemPackages` for lab infrastructure so the machine can
be recreated from the repo.

## Deploying `partridge`

From a checkout on `partridge`:

```sh
./scripts/nixos-switch.sh
```

The script uses `hostname -s` to select the matching flake target. It also
accepts other `nixos-rebuild` actions:

```sh
./scripts/nixos-switch.sh dry-build
./scripts/nixos-switch.sh build
./scripts/nixos-switch.sh test
./scripts/nixos-switch.sh boot
```

From another machine with SSH access:

```sh
nixos-rebuild switch --flake .#partridge --target-host edward@partridge --use-remote-sudo
```

## Prometheus Exporters

All Proxmox VM hosts include node exporter on port `9100` from
`nixos/modules/proxmox-vm-base.nix`.

`partridge` also exposes PostgreSQL metrics on port `9187`. The exporter runs
locally as the `postgres` Unix user, so it does not need a database password.

Example Prometheus scrape config:

```yaml
- job_name: partridge-node
  static_configs:
    - targets: ["partridge:9100"]

- job_name: partridge-postgres
  static_configs:
    - targets: ["partridge:9187"]
```

After switching the host, verify both endpoints:

```sh
curl http://partridge:9100/metrics
curl http://partridge:9187/metrics
```

## Tailscale

`partridge` runs Tailscale for remote access over the tailnet. After the first
switch that enables it, authenticate the machine once:

```sh
sudo tailscale up
```

Once authenticated, connect over the tailnet with normal SSH:

```sh
ssh edward@partridge
```

## Building An Image Later

NixOS can build images from normal system configurations with:

```sh
nixos-rebuild build-image --image-variant proxmox --flake .#image-name
```

This repo also exposes direct build outputs:

```sh
nix build .#image-name
```

`proxmox-vma` should be the native Proxmox backup/archive image format.
`proxmox-qcow-efi` is useful if importing a disk into an existing Terraform VM
is easier than restoring a VMA.

Run these from a machine with Nix installed. The Mac-side workspace currently
does not have the `nix` command available, so image builds need to happen from
the NixOS VM or another Nix builder.
