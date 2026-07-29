{ lib, pkgs, ... }:

{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 10;

  networking.useDHCP = lib.mkDefault true;

  services.openssh.enable = true;
  services.qemuGuest.enable = true;
  services.fstrim.enable = true;

  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = [ "systemd" ];
    openFirewall = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  users.users.edward = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    # Keep edward's systemd user manager persistently active. Otherwise a
    # short-lived SSH session churning open/closed during a `nixos-rebuild
    # switch` races the switch's "reload user units" step (logind loses the
    # uid-1000 user object mid-reload), failing the whole switch. Lingering
    # makes the deploy robust regardless of who is logged in.
    linger = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGW8YuC9dt9wq2LptMHCfrg8n5l0nGUAd227vWCbqKUD edward@m1"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzhdCoWE/CiY3laW9R/I5UEhQs7krz8ur8OOg7su5MJ edward@m2"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    curl
    git
    htop
    lazygit
    nettools
    ripgrep
    vim
    wget
  ];

  system.stateVersion = "25.11";
}
