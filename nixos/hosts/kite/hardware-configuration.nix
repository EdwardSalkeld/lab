# This host starts as a manually installed Proxmox VM on luna. During install,
# label the root filesystem `nixos` and EFI filesystem `BOOT`, or replace this
# file with the generated hardware configuration before switching.
{ lib, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.initrd.availableKernelModules = [
    "ata_piix"
    "uhci_hcd"
    "virtio_pci"
    "virtio_scsi"
    "sd_mod"
    "sr_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };

  # Dedicated app-state disks keep service metadata/cache off the OS root.
  # Media remains on external disks mounted below.
  fileSystems."/var/lib/jellyfin" = {
    device = "/dev/disk/by-label/jellyfin";
    fsType = "ext4";
    options = [
      "nofail"
      "x-systemd.device-timeout=1s"
    ];
  };

  fileSystems."/var/lib/navidrome" = {
    device = "/dev/disk/by-label/navidrome";
    fsType = "ext4";
    options = [
      "nofail"
      "x-systemd.device-timeout=1s"
    ];
  };

  fileSystems."/var/lib/wantlist" = {
    device = "/dev/disk/by-label/wantlist";
    fsType = "ext4";
    options = [
      "nofail"
      "x-systemd.device-timeout=1s"
    ];
  };

  fileSystems."/media" = {
    device = "/dev/disk/by-label/media";
    fsType = "ext4";
    options = [
      "nofail"
      "ro"
      "x-systemd.device-timeout=1s"
    ];
  };

  fileSystems."/music" = {
    device = "/dev/disk/by-label/music";
    fsType = "ext4";
    options = [
      "nofail"
      "ro"
      "x-systemd.device-timeout=1s"
    ];
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
