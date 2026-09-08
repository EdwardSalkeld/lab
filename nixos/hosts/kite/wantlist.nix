{ config, lib, mediaCollectionManagerPackages, ... }:

let
  cfg = config.alcachofa.kite.wantlist;
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
      WANTLIST_IMPORT_INBOX_PATH = cfg.importInbox;
      WANTLIST_MUSIC_DIR = cfg.musicDir;
      WANTLIST_TV_ROOT = cfg.tvRoot;
      WANTLIST_FILM_ROOT = cfg.filmRoot;
      WANTLIST_WORKSPACE_ROOT = cfg.workspaceRoot;
      WANTLIST_WATCHDIR_PATH = cfg.importInbox;
    };
    serviceConfig = {
      EnvironmentFile = config.sops.templates."wantlist.env".path;
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
  options.alcachofa.kite.wantlist = {
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
    sops.templates."wantlist.env" = {
      owner = "edward";
      group = "data";
      mode = "0400";
      content = ''
        WANTLIST_DATABASE_URL=${config.sops.placeholder."wantlist/database_url"}
        WANTLIST_SPOTIFY_CLIENT_ID=${config.sops.placeholder."wantlist/spotify_client_id"}
        WANTLIST_SPOTIFY_CLIENT_SECRET=${config.sops.placeholder."wantlist/spotify_client_secret"}
        WANTLIST_SPOTIFY_REDIRECT_URI=${config.sops.placeholder."wantlist/spotify_redirect_uri"}
        WANTLIST_TRANSMISSION_RPC_URL=${config.sops.placeholder."wantlist/transmission_rpc_url"}
        WANTLIST_TRANSMISSION_USER=${config.sops.placeholder."wantlist/transmission_user"}
        WANTLIST_TRANSMISSION_PASSWORD=${config.sops.placeholder."wantlist/transmission_password"}
        WANTLIST_TRANSMISSION_SSH_HOST=${config.sops.placeholder."wantlist/transmission_ssh_host"}
        WANTLIST_TRANSMISSION_SSH_USER=${config.sops.placeholder."wantlist/transmission_ssh_user"}
        WANTLIST_TRANSMISSION_SSH_KEY=${config.sops.secrets."wantlist/transmission_ssh_key".path}
        WANTLIST_NOTIFICATION_WEBHOOK_URL=${config.sops.placeholder."wantlist/notification_webhook_url"}
      '';
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/wantlist 0750 edward data -"
    ];

    systemd.services.wantlist-migrate = common // {
      description = "Apply Media Collection Manager database migrations";
      before = [
        "wantlist-api.service"
        "wantlist-worker.service"
      ];
      serviceConfig = common.serviceConfig // {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        exec ${mediaCollectionManagerPackages.wantlist-migrate}/bin/wantlist-migrate upgrade head
      '';
    };

    systemd.services.wantlist-api = common // {
      description = "Media Collection Manager API and frontend";
      after = common.after ++ [ "wantlist-migrate.service" ];
      requires = [ "wantlist-migrate.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = common.serviceConfig // {
        Restart = "on-failure";
        RestartSec = "5s";
      };
      script = ''
        exec ${mediaCollectionManagerPackages.wantlist-api}/bin/wantlist-api
      '';
    };

    systemd.services.wantlist-worker = common // {
      description = "Media Collection Manager worker";
      after = common.after ++ [ "wantlist-migrate.service" ];
      requires = [ "wantlist-migrate.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = common.serviceConfig // {
        Restart = "on-failure";
        RestartSec = "5s";
      };
      script = ''
        exec ${mediaCollectionManagerPackages.wantlist-worker}/bin/wantlist-worker
      '';
    };
  };
}
