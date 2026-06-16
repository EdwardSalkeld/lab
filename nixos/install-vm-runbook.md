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

## 5. Mount the Target Filesystems

```sh
mount "$ROOT" /mnt
mkdir -p /mnt/boot
mount "$BOOT" /mnt/boot
```

For `magpie`, the repo already contains a hardware config that expects the
labels above, so there is no need to run `nixos-generate-config` during a normal
reinstall.

## 6. Install NixOS From the Repo Flake

Install directly from the GitHub flake:

```sh
export NIX_CONFIG="experimental-features = nix-command flakes"
nixos-install --flake github:EdwardSalkeld/lab#magpie --no-root-passwd
```

If installing from an unmerged branch, include the branch name in the flake URL:

```sh
nixos-install --flake github:EdwardSalkeld/lab/add-magpie-dev-vm#magpie --no-root-passwd
```

The repo config creates the `edward` user, installs the configured SSH keys,
enables SSH, and enables the QEMU guest agent.

Before rebooting, switch the VM boot order in Proxmox so the installed disk
boots before the ISO. Removing or detaching the ISO is also fine. If this is
missed, the VM will boot back into the installer.

Then reboot:

```sh
reboot
```

## 7. Confirm the Installed Host

After reboot, SSH into the installed VM as `edward`:

```sh
ssh edward@<vm-ip>
```

The system is already installed from the repo flake. From a checkout on the VM,
future updates can use:

```sh
./scripts/nixos-switch.sh
```

The script uses `hostname -s` to select the matching flake target. Without a
checkout, rebuild directly from GitHub:

```sh
sudo nixos-rebuild switch --flake github:EdwardSalkeld/lab#magpie
```

If a switch needs to be undone later, the same helper also supports:

```sh
./scripts/nixos-switch.sh rollback
```

That shortcut runs an immediate rollback via `nixos-rebuild switch --rollback`
without needing to repeat the flake target manually.

## 8. Post-Install Checks

```sh
hostname
systemctl is-active sshd
systemctl is-active qemu-guest-agent
nixos-rebuild dry-build --flake .#magpie
```

If the host should be disposable, avoid storing important state on its root disk
unless Terraform also manages a separate persistent disk for that state.
