{
  config,
  lib,
  wantlistFrontend,
  wantlistPackage,
  wantlistSrc,
  ...
}:

let
  cfg = config.alcachofa.kite.wantlist;
  appEnvironment = {
    BEETSDIR = cfg.beetsDir;
    WANTLIST_IMPORT_INBOX_PATH = cfg.importInbox;
    WANTLIST_MUSIC_DIR = cfg.musicDir;
    WANTLIST_STATIC_DIR = "${wantlistFrontend}/dist";
    WANTLIST_TV_ROOT = cfg.tvRoot;
    WANTLIST_WORKSPACE_ROOT = cfg.workspaceRoot;
    WANTLIST_FILM_ROOT = cfg.filmRoot;
  };
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
      "/var/lib/wantlist"
    ];
    serviceConfig = {
      EnvironmentFile = cfg.environmentFile;
      Group = "data";
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
        cfg.workspaceRoot
        cfg.filmRoot
      ];
      User = "edward";
      WorkingDirectory = "${wantlistSrc}/backend";
    };
    environment = appEnvironment;
  };
in
{
  options.alcachofa.kite.wantlist = {
    enable = lib.mkEnableOption "native Wantlist API, migration, and worker services";

    environmentFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/secrets/wantlist.env";
      description = "SOPS-rendered Wantlist environment file.";
    };

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
    systemd.services.wantlist-migrate = common // {
      description = "Apply Wantlist database migrations";
      serviceConfig = common.serviceConfig // {
        Type = "oneshot";
      };
      script = ''
        exec ${wantlistPackage}/bin/wantlist -m alembic -c ${wantlistSrc}/backend/alembic.ini upgrade head
      '';
    };

    systemd.services.wantlist-api = common // {
      description = "Wantlist API and frontend";
      after = common.after ++ [ "wantlist-migrate.service" ];
      requires = [ "wantlist-migrate.service" ];
      serviceConfig = common.serviceConfig // {
        Restart = "on-failure";
        RestartSec = "5s";
      };
      script = ''
        exec ${wantlistPackage}/bin/wantlist -m uvicorn wantlist.app:app --host 127.0.0.1 --port 8000
      '';
    };

    systemd.services.wantlist-worker = common // {
      description = "Wantlist scheduler and import worker";
      after = common.after ++ [ "wantlist-migrate.service" ];
      requires = [ "wantlist-migrate.service" ];
      serviceConfig = common.serviceConfig // {
        Restart = "on-failure";
        RestartSec = "5s";
      };
      script = ''
        exec ${wantlistPackage}/bin/wantlist -m wantlist.worker
      '';
    };

    systemd.targets.wantlist = {
      description = "Wantlist services";
      after = [ "wantlist-migrate.service" ];
      requires = [ "wantlist-migrate.service" ];
      wants = [
        "wantlist-api.service"
        "wantlist-worker.service"
      ];
      wantedBy = [ "multi-user.target" ];
    };
  };
}
