{ pkgs, ... }:

{
  imports = [
    ./docker-stacks.nix
    ./hardware-configuration.nix
    ./media-services.nix
    ./observability.nix
    ./reverse-proxy.nix
  ];

  networking.hostName = "blink";
  networking.networkmanager.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  services.openssh.enable = true;

  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  users.users.edward = {
    isNormalUser = true;
    extraGroups = [
      "docker"
      "networkmanager"
      "wheel"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGW8YuC9dt9wq2LptMHCfrg8n5l0nGUAd227vWCbqKUD edward@m1"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzhdCoWE/CiY3laW9R/I5UEhQs7krz8ur8OOg7su5MJ edward@m2"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    curl
    docker-compose
    git
    htop
    jq
    ripgrep
    smartmontools
    vim
    wget
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  system.stateVersion = "25.11";
}
