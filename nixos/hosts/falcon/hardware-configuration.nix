{ modulesPath, ... }:

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.initrd.availableKernelModules = [ "ahci" "virtio_pci" "virtio_blk" "virtio_scsi" "sd_mod" ];
  # The Hetzner Rescue environment is booted in legacy BIOS mode. Keep the
  # installed system compatible with that firmware rather than installing an
  # EFI-only bootloader.
  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
  };

  fileSystems."/" = {
    # Assigned during the Rescue installation. Labels survive disk-device
    # enumeration changes and avoid referring to Debian's obsolete UUIDs.
    device = "/dev/disk/by-label/NIXOS_ROOT";
    fsType = "ext4";
  };

}
