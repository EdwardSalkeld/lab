{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "kite";
  networking.networkmanager.enable = true;
  networking.firewall = {
    trustedInterfaces = [ "tailscale0" ];
    allowedTCPPorts = [
      4533
      8000
      8096
    ];
  };

  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

  services.navidrome = {
    enable = true;
    openFirewall = true;
    settings = {
      Address = "0.0.0.0";
      Port = 4533;
      MusicFolder = "/data/partial/record-library/library";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/jellyfin/cache 0750 jellyfin jellyfin -"
  ];

  users.groups.media = {
    gid = 1001;
  };

  users.users.jellyfin.extraGroups = [ "media" ];

  users.users.edward.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAbd34g7lWe3qsntjGhdgLVFSSdh9BvrFDTqlNADdZvD edward@fourth"
  ];

  alcachofa.remoteDeploy.postSwitchHealthchecks = [
    "jellyfin.service"
    "navidrome.service"
    "tailscaled.service"
    "qemu-guest-agent.service"
  ];

  systemd.services.jellyfin = {
    after = [
      "media.mount"
      "var-lib-jellyfin.mount"
    ];
    wants = [
      "media.mount"
      "var-lib-jellyfin.mount"
    ];
    unitConfig.ConditionPathIsMountPoint = [
      "/var/lib/jellyfin"
      "/media"
    ];
  };

  systemd.services.navidrome = {
    after = [
      "data.mount"
      "var-lib-navidrome.mount"
    ];
    wants = [
      "data.mount"
      "var-lib-navidrome.mount"
    ];
    unitConfig.ConditionPathIsMountPoint = [
      "/var/lib/navidrome"
      "/data"
    ];
  };

  environment.systemPackages = with pkgs; [
    curl
    git
    ghostty.terminfo
    htop
    rsync
    smartmontools
    sqlite
    tree
    vim
  ];
}
