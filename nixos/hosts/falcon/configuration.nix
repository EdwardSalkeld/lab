{ lib, pkgs, tailscalePackage ? pkgs.tailscale, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./freshrss.nix
  ];

  networking = {
    hostName = "falcon";
    useDHCP = false;
    defaultGateway6 = {
      address = "fe80::1";
      interface = "eth0";
    };
    interfaces.eth0 = {
      # Hetzner Cloud assigns and routes the Primary IPv4 over DHCP. Keeping
      # this dynamic lets a reassigned Primary IP work without a host change.
      useDHCP = true;
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
    # Read service logs but retain no administrative or sudo access.
    extraGroups = [ "systemd-journal" ];
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7g5CoTIOcrTpzDqFylWrcMGJIqOQC2RrYcWQzhD4NTB8Uh5ZHhR0LMfRhFXivIs3TY+bAe4ov7FODCOimL6irSoj6Pd/2La3o3hXGz2u/l1/7sLWxtG3H7k2QCOHacVzZUznJpn4rAGtfq2w8cmF/RNO1kc/ZncaIlh2TZ8f3D5cAEKUV2f7YN40d9MSnXNgg6YRgL91wfWDO7DMuWUi5UTqcH/3NBcJXsrTEQ7TT10ISabIVoLNROoAiORZY83iy1fYSGN3u3t72qcVdRIW1vZ7JbgaJ1ue4z2r1LkCKz4bGw3U76joloAv/V6rYR3o4+69atJaPhGapqiu8EkDF0eGjbfEzBi1sLehrzNH21Kv0TbNfwvUecCrvqZqNAhxPiedx1ws5BBcYDjAKpP3YU0hdmjoFDlBX4oFR7NhJ4lLWhAxgqCmzNvJAdFG0pya7hhsivc57vUibkdnRjNIJN+U3zwyT8xmRSiuaH8G1J1dDKjuMwlK0T2B4AsAwoJM= billy@chatting"
    ];
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
