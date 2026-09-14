{ modulesPath, ... }:

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.initrd.availableKernelModules = [ "ahci" "virtio_pci" "virtio_blk" "virtio_scsi" "sd_mod" ];
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  fileSystems."/" = {
    # Assigned during the Rescue installation. Labels survive disk-device
    # enumeration changes and avoid referring to Debian's obsolete UUIDs.
    device = "/dev/disk/by-label/NIXOS_ROOT";
    fsType = "ext4";
  };

  fileSystems."/boot/efi" = {
    device = "/dev/disk/by-label/NIXOS_EFI";
    fsType = "vfat";
    options = [ "umask=0077" ];
  };
}
