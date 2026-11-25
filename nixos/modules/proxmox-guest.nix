# Boot and hardware settings for a NixOS VM running under Proxmox.
{ lib, ... }:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 10;

  networking.useDHCP = lib.mkDefault true;

  services.qemuGuest.enable = true;
  services.fstrim.enable = true;
}
