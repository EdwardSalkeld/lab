{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "partridge";
  networking.networkmanager.enable = true;

  fileSystems."/srv/code" = {
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1";
    fsType = "ext4";
  };

  fileSystems."/var/lib/postgresql" = {
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi2";
    fsType = "ext4";
  };

  services.postgresql.enable = true;

  users.users.edward.packages = with pkgs; [
    tree
  ];

  environment.systemPackages = with pkgs; [
    git
    vim
    wget
  ];
}
