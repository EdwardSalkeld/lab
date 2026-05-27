## NixOS Configurations

This directory is the start of the repo-owned NixOS configuration.

Current targets:

- `partridge`: the first repo-managed NixOS VM.

Draft configs may exist for future hosts/images, but only `partridge` is wired
into `flake.nix` right now.

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

After `nixos-01` is adopted into this repo, add shared packages to
`nixos/modules/proxmox-vm-base.nix`, then rebuild the host:

```sh
sudo nixos-rebuild switch --flake .#nixos-01
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

## Adopting `nixos-01`

Before using `.#nixos-01` against the live VM, copy the generated hardware
configuration into this repo:

```sh
scp edward@nixos-01:/etc/nixos/hardware-configuration.nix \
  nixos/hosts/nixos-01/hardware-configuration.nix
```

Then uncomment the import in `nixos/hosts/nixos-01/configuration.nix`.

## Deploying `partridge`

From a checkout on `partridge`:

```sh
sudo nixos-rebuild switch --flake .#partridge
```

From another machine with SSH access:

```sh
nixos-rebuild switch --flake .#partridge --target-host edward@partridge --use-remote-sudo
```

## Building An Image Later

NixOS can build images from normal system configurations with:

```sh
nixos-rebuild build-image --image-variant proxmox --flake .#proxmox-image
```

This repo also exposes direct build outputs:

```sh
nix build .#proxmox-vma
nix build .#proxmox-qcow-efi
```

`proxmox-vma` should be the native Proxmox backup/archive image format.
`proxmox-qcow-efi` is useful if importing a disk into an existing Terraform VM
is easier than restoring a VMA.

Run these from a machine with Nix installed. The Mac-side workspace currently
does not have the `nix` command available, so image builds need to happen from
the NixOS VM or another Nix builder.
