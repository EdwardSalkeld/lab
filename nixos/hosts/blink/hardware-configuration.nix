# Bare-metal hardware profile for blink.
#
# During a fresh install, label the new filesystems to match this file:
# - root ext4: nixos
# - EFI vfat: BOOT
# - swap: swap
#
# Existing data disks are pinned by UUID and should not be reformatted.
{ lib, ... }:

{
  boot.initrd.availableKernelModules = [
    "ahci"
    "sd_mod"
    "uas"
    "usb_storage"
    "xhci_pci"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot/efi" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  fileSystems."/mnt/redhdd" = {
    device = "/dev/disk/by-uuid/a1666c44-85b1-406a-8f25-8e1a67f8a4dc";
    fsType = "ext4";
  };

  fileSystems."/mnt/ext2tb/1" = {
    device = "/dev/disk/by-uuid/660cb924-f09f-4543-995c-e23ff39af77b";
    fsType = "ext4";
  };

  fileSystems."/mnt/ext2tb/3" = {
    device = "/dev/disk/by-uuid/0cdabdee-8fcc-4143-8189-3911d477108e";
    fsType = "ext4";
  };

  fileSystems."/mnt/ext2tb/4" = {
    device = "/dev/disk/by-uuid/74d9c4e7-710b-4dd3-a8a1-726badebb770";
    fsType = "ext4";
  };

  fileSystems."/mnt/ssd4tb" = {
    device = "/dev/disk/by-uuid/836b5915-74d0-4801-a2f3-aa32f54730db";
    fsType = "ext4";
  };

  swapDevices = [
    { device = "/dev/disk/by-label/swap"; }
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
