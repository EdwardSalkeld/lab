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
      MusicFolder = "/music";
    };
  };

  systemd.services.jellyfin = {
    after = [
      "media.mount"
      "music.mount"
      "var-lib-jellyfin.mount"
    ];
    wants = [
      "media.mount"
      "music.mount"
      "var-lib-jellyfin.mount"
    ];
    unitConfig.ConditionPathIsMountPoint = [
      "/var/lib/jellyfin"
      "/media"
      "/music"
    ];
  };

  systemd.services.navidrome = {
    after = [
      "music.mount"
      "var-lib-navidrome.mount"
    ];
    wants = [
      "music.mount"
      "var-lib-navidrome.mount"
    ];
    unitConfig.ConditionPathIsMountPoint = [
      "/var/lib/navidrome"
      "/music"
    ];
  };

  environment.systemPackages = with pkgs; [
    curl
    git
    htop
    rsync
    smartmontools
    tree
    vim
  ];
}
