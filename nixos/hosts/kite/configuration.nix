{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./web.nix
    ./mcm.nix
  ];

  networking.hostName = "kite";
  networking.networkmanager.enable = true;
  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  services.jellyfin = {
    enable = true;
  };

  services.navidrome = {
    enable = true;
    settings = {
      Address = "127.0.0.1";
      Port = 4533;
      MusicFolder = "/data/partial/record-library/library";
    };
  };

  alcachofa.kite.mcm.enable = true;

  systemd.tmpfiles.rules = [
    "d /var/lib/jellyfin/cache 0750 jellyfin jellyfin -"
  ];

  users.groups.media = {
    gid = 1001;
  };

  # GID 1000 is the historical group ownership recorded on migrated data.
  users.groups.data = {
    gid = 1000;
  };

  # The migrated /data filesystem records Edward's historical UID (1000).
  # Keep that identity on Kite so Fourth's unprivileged backup account can
  # read the existing data without relaxing filesystem permissions.
  users.users.edward = {
    uid = 1000;
    extraGroups = [
      "data"
      "jellyfin"
      "media"
    ];
  };

  # `billy` is inherited from the shared VM base but is not used on Kite.
  # Move it away from the UID preserved on the migrated data disk.
  users.users.billy = {
    uid = 1002;
    extraGroups = [ "wheel" ];
  };

  users.users.jellyfin.extraGroups = [ "media" ];

  users.users.edward.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAbd34g7lWe3qsntjGhdgLVFSSdh9BvrFDTqlNADdZvD edward@fourth"
  ];

  alcachofa.remoteDeploy.postSwitchHealthchecks = [
    "jellyfin.service"
    "navidrome.service"
    "mcm-api.service"
    "mcm-worker.service"
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
