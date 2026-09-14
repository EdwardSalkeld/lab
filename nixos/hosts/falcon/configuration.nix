{ lib, pkgs, tailscalePackage ? pkgs.tailscale, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./freshrss.nix
  ];

  networking = {
    hostName = "falcon";
    useDHCP = false;
    defaultGateway = {
      address = "172.31.1.1";
      interface = "eth0";
    };
    defaultGateway6 = {
      address = "fe80::1";
      interface = "eth0";
    };
    interfaces.eth0 = {
      ipv4.addresses = [{ address = "91.99.120.43"; prefixLength = 32; }];
      ipv6.addresses = [{ address = "2a01:4f8:c17:d035::1"; prefixLength = 64; }];
    };
    firewall.allowedTCPPorts = [ 22 80 443 9100 ];
  };

  services.openssh.enable = true;
  services.tailscale = {
    enable = true;
    package = tailscalePackage;
    openFirewall = true;
    extraUpFlags = [ "--advertise-exit-node" ];
  };
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = [ "systemd" ];
    openFirewall = true;
  };

  users.users.edward = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGW8YuC9dt9wq2LptMHCfrg8n5l0nGUAd227vWCbqKUD edward@m1"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzhdCoWE/CiY3laW9R/I5UEhQs7krz8ur8OOg7su5MJ edward@m2"
    ];
  };
  users.users.billy = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };
  security.sudo.wheelNeedsPassword = false;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  environment.systemPackages = with pkgs; [ curl git htop jq ripgrep vim wget ];

  system.stateVersion = "26.05";
}
