{ config, lib, mediaCollectionManagerPackages, ... }:

let
  cfg = config.alcachofa.kite.mcm;
  # Keep the existing Wantlist-named state and SOPS entries in place. Renaming
  # these would require moving persistent data and re-encrypting credentials.
  common = {
    after = [
      "data.mount"
      "media.mount"
      "network-online.target"
      "var-lib-wantlist.mount"
    ];
    wants = [ "network-online.target" ];
    unitConfig.ConditionPathIsMountPoint = [
      "/data"
      "/media"
    ];
    environment = {
      BEETSDIR = cfg.beetsDir;
      HOME = "/var/lib/wantlist";
      MCM_BEETS_DIRECTORY = cfg.musicDir;
      MCM_IMPORT_INBOX_PATH = cfg.importInbox;
      MCM_MUSIC_DIR = cfg.musicDir;
      MCM_TV_ROOT = cfg.tvRoot;
      MCM_FILM_ROOT = cfg.filmRoot;
      MCM_WORKSPACE_ROOT = cfg.workspaceRoot;
      MCM_WATCHDIR_PATH = cfg.importInbox;
    };
    serviceConfig = {
      EnvironmentFile = config.sops.templates."mcm.env".path;
      User = "edward";
      Group = "data";
      SupplementaryGroups = [ "media" ];
      UMask = "0027";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [
        "/var/lib/wantlist"
        cfg.beetsDir
        cfg.importInbox
        cfg.musicDir
        cfg.tvRoot
        cfg.filmRoot
        cfg.workspaceRoot
      ];
    };
  };
in
{
  options.alcachofa.kite.mcm = {
    enable = lib.mkEnableOption "Media Collection Manager services";

    beetsDir = lib.mkOption {
      type = lib.types.str;
      default = "/data/partial/record-library";
    };

    musicDir = lib.mkOption {
      type = lib.types.str;
      default = "/data/partial/record-library/library";
    };

    importInbox = lib.mkOption {
      type = lib.types.str;
      default = "/data/partial/record-library/inbox";
    };

    tvRoot = lib.mkOption {
      type = lib.types.str;
      default = "/media/tv";
    };

    filmRoot = lib.mkOption {
      type = lib.types.str;
      default = "/media/film";
    };

    workspaceRoot = lib.mkOption {
      type = lib.types.str;
      default = "/media/workspace";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."wantlist/database_url" = {
      sopsFile = ./secrets/wantlist.yaml;
      key = "database_url";
      owner = "edward";
      group = "data";
      mode = "0400";
    };
    sops.secrets = {
      "wantlist/spotify_client_id" = {
        sopsFile = ./secrets/wantlist.yaml;
        key = "spotify_client_id";
        owner = "edward";
        group = "data";
        mode = "0400";
      };
      "wantlist/spotify_client_secret" = {
        sopsFile = ./secrets/wantlist.yaml;
        key = "spotify_client_secret";
        owner = "edward";
        group = "data";
        mode = "0400";
      };
      "wantlist/spotify_redirect_uri" = {
        sopsFile = ./secrets/wantlist.yaml;
        key = "spotify_redirect_uri";
        owner = "edward";
        group = "data";
        mode = "0400";
      };
      "wantlist/transmission_rpc_url" = {
        sopsFile = ./secrets/wantlist.yaml;
        key = "transmission_rpc_url";
        owner = "edward";
        group = "data";
        mode = "0400";
      };
      "wantlist/transmission_user" = {
        sopsFile = ./secrets/wantlist.yaml;
        key = "transmission_user";
        owner = "edward";
        group = "data";
        mode = "0400";
      };
      "wantlist/transmission_password" = {
        sopsFile = ./secrets/wantlist.yaml;
        key = "transmission_password";
        owner = "edward";
        group = "data";
        mode = "0400";
      };
      "wantlist/transmission_ssh_host" = {
        sopsFile = ./secrets/wantlist.yaml;
        key = "transmission_ssh_host";
        owner = "edward";
        group = "data";
        mode = "0400";
      };
      "wantlist/transmission_ssh_user" = {
        sopsFile = ./secrets/wantlist.yaml;
        key = "transmission_ssh_user";
        owner = "edward";
        group = "data";
        mode = "0400";
      };
      "wantlist/transmission_ssh_key" = {
        sopsFile = ./secrets/wantlist.yaml;
        key = "transmission_ssh_key";
        owner = "edward";
        group = "data";
        mode = "0400";
      };
      "wantlist/notification_webhook_url" = {
        sopsFile = ./secrets/wantlist.yaml;
        key = "notification_webhook_url";
        owner = "edward";
        group = "data";
        mode = "0400";
      };
    };
    sops.templates."mcm.env" = {
      owner = "edward";
      group = "data";
      mode = "0400";
      content = ''
        MCM_DATABASE_URL=${config.sops.placeholder."wantlist/database_url"}
        MCM_SPOTIFY_CLIENT_ID=${config.sops.placeholder."wantlist/spotify_client_id"}
        MCM_SPOTIFY_CLIENT_SECRET=${config.sops.placeholder."wantlist/spotify_client_secret"}
        MCM_SPOTIFY_REDIRECT_URI=${config.sops.placeholder."wantlist/spotify_redirect_uri"}
        MCM_TRANSMISSION_RPC_URL=${config.sops.placeholder."wantlist/transmission_rpc_url"}
        MCM_TRANSMISSION_USER=${config.sops.placeholder."wantlist/transmission_user"}
        MCM_TRANSMISSION_PASSWORD=${config.sops.placeholder."wantlist/transmission_password"}
        MCM_TRANSMISSION_SSH_HOST=${config.sops.placeholder."wantlist/transmission_ssh_host"}
        MCM_TRANSMISSION_SSH_USER=${config.sops.placeholder."wantlist/transmission_ssh_user"}
        MCM_TRANSMISSION_SSH_KEY=${config.sops.secrets."wantlist/transmission_ssh_key".path}
        MCM_NOTIFICATION_WEBHOOK_URL=${config.sops.placeholder."wantlist/notification_webhook_url"}
      '';
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/wantlist 0750 edward data -"
    ];

    systemd.services.mcm-migrate = common // {
      description = "Apply Media Collection Manager database migrations";
      before = [
        "mcm-api.service"
        "mcm-worker.service"
      ];
      serviceConfig = common.serviceConfig // {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        exec ${mediaCollectionManagerPackages.mcm-migrate}/bin/mcm-migrate upgrade head
      '';
    };

    systemd.services.mcm-api = common // {
      description = "Media Collection Manager API and frontend";
      after = common.after ++ [ "mcm-migrate.service" ];
      requires = [ "mcm-migrate.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = common.serviceConfig // {
        Restart = "on-failure";
        RestartSec = "5s";
      };
      script = ''
        exec ${mediaCollectionManagerPackages.mcm-api}/bin/mcm-api
      '';
    };

    systemd.services.mcm-worker = common // {
      description = "Media Collection Manager worker";
      after = common.after ++ [ "mcm-migrate.service" ];
      requires = [ "mcm-migrate.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = common.serviceConfig // {
        Restart = "on-failure";
        RestartSec = "5s";
      };
      script = ''
        exec ${mediaCollectionManagerPackages.mcm-worker}/bin/mcm-worker
      '';
    };
  };
}
