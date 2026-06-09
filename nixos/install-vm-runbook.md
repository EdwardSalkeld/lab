# Installing a New NixOS VM

This runbook covers the repo's current bootstrap flow for Proxmox-managed NixOS
VMs. Terraform creates the VM, attaches the stock NixOS minimal ISO, and boots
it. Use the Proxmox console only long enough to enable SSH, then do the install
from a local terminal.

## 1. Create the VM

From this repo, load Terraform credentials and apply the VM config:

```sh
set -a
source terraform/.env
set +a
terraform -chdir=terraform apply
```

For a disposable VM such as `magpie`, it is fine to destroy and recreate the VM
while iterating.

## 2. Start SSH From Proxmox Console

Open the VM console in Proxmox. At the NixOS installer prompt, set a temporary
root password and start SSH:

```sh
sudo passwd root
sudo systemctl start sshd
ip -4 addr show
```

Note the VM's IPv4 address, then leave the Proxmox console alone.

## 3. SSH Into the Installer

From a local terminal:

```sh
ssh root@<installer-ip>
```

Confirm the target disk. For the current `magpie` Terraform config, prefer the
stable serial-based path:

```sh
ls -l /dev/disk/by-id/
export DISK=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_magpie-root
lsblk "$DISK"
```

If that path is not present, identify the blank VM disk with:

```sh
lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS,MODEL,SERIAL
```

## 4. Partition and Format

This destroys the selected disk.

```sh
parted "$DISK" -- mklabel gpt
parted "$DISK" -- mkpart ESP fat32 1MiB 512MiB
parted "$DISK" -- set 1 esp on
parted "$DISK" -- mkpart primary ext4 512MiB 100%
```

Re-read the partition table and find the partition paths:

```sh
partprobe "$DISK"
lsblk -f "$DISK"
```

For `/dev/disk/by-id/...`, partition paths are usually the disk path with
`-part1` and `-part2` appended:

```sh
export BOOT="${DISK}-part1"
export ROOT="${DISK}-part2"
```

Format with labels expected by the checked-in hardware config:

```sh
mkfs.fat -F 32 -n BOOT "$BOOT"
mkfs.ext4 -F -L nixos "$ROOT"
```

## 5. Mount and Generate Config

```sh
mount "$ROOT" /mnt
mkdir -p /mnt/boot
mount "$BOOT" /mnt/boot
nixos-generate-config --root /mnt
```

If this is a new host, copy `/mnt/etc/nixos/hardware-configuration.nix` back
into the repo later. For `magpie`, the repo already contains a hardware config
that expects the labels above.

## 6. Install NixOS

For the first install, use a minimal temporary config so the machine boots and
has SSH:

```sh
nano /mnt/etc/nixos/configuration.nix
```

Minimal shape:

```nix
{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "magpie";
  networking.networkmanager.enable = true;

  services.openssh.enable = true;

  environment.systemPackages = with pkgs; [
    git
  ];

  users.users.edward = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGW8YuC9dt9wq2LptMHCfrg8n5l0nGUAd227vWCbqKUD edward@m1"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzhdCoWE/CiY3laW9R/I5UEhQs7krz8ur8OOg7su5MJ edward@m2"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "25.11";
}
```

Install:

```sh
nixos-install
```

Before rebooting, switch the VM boot order in Proxmox so the installed disk
boots before the ISO. Removing or detaching the ISO is also fine. If this is
missed, the VM will boot back into the installer.

Then reboot:

```sh
reboot
```

## 7. Switch to Repo Config

After reboot, SSH into the installed VM as `edward`:

```sh
ssh edward@<vm-ip>
```

Clone this repo or copy the existing checkout, then switch to the flake config:

```sh
./scripts/nixos-switch.sh
```

The script uses `hostname -s` to select the matching flake target.

## 8. Post-Install Checks

```sh
hostname
systemctl is-active sshd
systemctl is-active qemu-guest-agent
nixos-rebuild dry-build --flake .#magpie
```

If the host should be disposable, avoid storing important state on its root disk
unless Terraform also manages a separate persistent disk for that state.
