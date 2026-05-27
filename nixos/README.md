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
sudo nixos-rebuild switch --flake .#partridge
```

From another machine with SSH access:

```sh
nixos-rebuild switch --flake .#partridge --target-host edward@partridge --use-remote-sudo
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
