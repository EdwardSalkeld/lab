{ config, pkgs, bitwardenMirrorPackage, ... }:

let
  user = "bitwarden-mirror";
  group = "bitwarden-mirror";
in
{
  sops.defaultSopsFile = ./secrets/bitwarden-mirror.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  sops.secrets = {
    "bitwarden-mirror/source_bw_clientid" = {
      key = "source_bw_clientid";
      owner = user;
      inherit group;
    };
    "bitwarden-mirror/source_bw_clientsecret" = {
      key = "source_bw_clientsecret";
      owner = user;
      inherit group;
    };
    "bitwarden-mirror/source_bw_master_password" = {
      key = "source_bw_master_password";
      owner = user;
      inherit group;
    };
    "bitwarden-mirror/dest_bw_clientid" = {
      key = "dest_bw_clientid";
      owner = user;
      inherit group;
    };
    "bitwarden-mirror/dest_bw_clientsecret" = {
      key = "dest_bw_clientsecret";
      owner = user;
      inherit group;
    };
    "bitwarden-mirror/dest_bw_master_password" = {
      key = "dest_bw_master_password";
      owner = user;
      inherit group;
    };
  };

  sops.templates."bitwarden-mirror.env" = {
    owner = user;
    inherit group;
    mode = "0400";
    content = ''
      SOURCE_BW_CLIENTID=${config.sops.placeholder."bitwarden-mirror/source_bw_clientid"}
      SOURCE_BW_CLIENTSECRET=${config.sops.placeholder."bitwarden-mirror/source_bw_clientsecret"}
      SOURCE_BW_MASTER_PASSWORD=${config.sops.placeholder."bitwarden-mirror/source_bw_master_password"}
      DEST_BW_CLIENTID=${config.sops.placeholder."bitwarden-mirror/dest_bw_clientid"}
      DEST_BW_CLIENTSECRET=${config.sops.placeholder."bitwarden-mirror/dest_bw_clientsecret"}
      DEST_BW_MASTER_PASSWORD=${config.sops.placeholder."bitwarden-mirror/dest_bw_master_password"}
    '';
  };

  users.groups.${group} = { };
  users.users.${user} = {
    isSystemUser = true;
    inherit group;
    home = "/var/lib/bitwarden-mirror";
    createHome = true;
  };

  systemd.services.bitwarden-vaultwarden-mirror = {
    description = "Refresh Vaultwarden mirror from Bitwarden cloud";
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "vaultwarden.service"
    ];
    path = [
      bitwardenMirrorPackage
      pkgs.bitwarden-cli
    ];
    serviceConfig = {
      Type = "oneshot";
      User = user;
      Group = group;
      EnvironmentFile = config.sops.templates."bitwarden-mirror.env".path;
      ExecStart = "${bitwardenMirrorPackage}/bin/bitwarden-mirror";
      RuntimeDirectory = "bitwarden-mirror";
      RuntimeDirectoryMode = "0700";
      StateDirectory = "bitwarden-mirror";
      StateDirectoryMode = "0700";
      PrivateTmp = true;
      NoNewPrivileges = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [
        "/run/bitwarden-mirror"
        "/var/lib/bitwarden-mirror"
      ];
    };
  };

  systemd.timers.bitwarden-vaultwarden-mirror = {
    description = "Nightly Vaultwarden mirror refresh";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 03:20:00";
      Persistent = true;
      RandomizedDelaySec = "20m";
      Unit = "bitwarden-vaultwarden-mirror.service";
    };
  };
}
