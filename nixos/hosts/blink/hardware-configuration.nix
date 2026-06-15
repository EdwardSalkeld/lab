{ lib, ... }:

{
  boot.initrd.availableKernelModules = [
    "ahci"
    "sd_mod"
    "uas"
    "usb_storage"
    "xhci_pci"
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 10;

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/00bbc154-b0d3-4049-aaeb-3423afa205f0";
    fsType = "ext4";
  };

  fileSystems."/boot/efi" = {
    device = "/dev/disk/by-uuid/ABCE-3FC7";
    fsType = "vfat";
  };

  fileSystems."/mnt/ext2tb/1" = {
    device = "/dev/disk/by-uuid/660cb924-f09f-4543-995c-e23ff39af77b";
    fsType = "ext4";
    options = [
      "nofail"
      "x-systemd.device-timeout=30s"
    ];
  };

  fileSystems."/mnt/ext2tb/3" = {
    device = "/dev/disk/by-uuid/0cdabdee-8fcc-4143-8189-3911d477108e";
    fsType = "ext4";
    options = [
      "nofail"
      "x-systemd.device-timeout=30s"
    ];
  };

  fileSystems."/mnt/ext2tb/4" = {
    device = "/dev/disk/by-uuid/74d9c4e7-710b-4dd3-a8a1-726badebb770";
    fsType = "ext4";
    options = [
      "nofail"
      "x-systemd.device-timeout=30s"
    ];
  };

  fileSystems."/mnt/ssd4tb" = {
    device = "/dev/disk/by-uuid/836b5915-74d0-4801-a2f3-aa32f54730db";
    fsType = "ext4";
    options = [
      "nofail"
      "x-systemd.device-timeout=30s"
    ];
  };

  fileSystems."/mnt/redhdd" = {
    device = "/dev/disk/by-uuid/a1666c44-85b1-406a-8f25-8e1a67f8a4dc";
    fsType = "ext4";
    options = [
      "nofail"
      "x-systemd.device-timeout=30s"
    ];
  };

  swapDevices = [
    { device = "/dev/disk/by-uuid/669a03ca-0f1d-4832-b163-a483d6ea8e27"; }
  ];

  networking.useDHCP = lib.mkDefault true;
}
