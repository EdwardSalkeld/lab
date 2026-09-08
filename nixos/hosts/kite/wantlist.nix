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
    sops.templates."wantlist.env" = {
      owner = "edward";
      group = "data";
      mode = "0400";
      content = ''
        WANTLIST_DATABASE_URL=${config.sops.placeholder."wantlist/database_url"}
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
