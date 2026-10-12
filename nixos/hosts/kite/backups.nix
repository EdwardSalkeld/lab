{ config, lib, ... }:

let
  cfg = config.alcachofa.kite.backups;
in
{
  options.alcachofa.kite.backups = {
    enable = lib.mkEnableOption "Kite's off-site data backup";
  };

  config = lib.mkIf cfg.enable {
    # Before the first deployment, add the existing Restic/B2 values to
    # kite-backup.yaml. The accompanying .example file documents those values.
    sops.secrets = {
      "kite-backup/restic_repository" = {
        sopsFile = ./secrets/kite-backup.yaml;
        key = "restic_repository";
      };
      "kite-backup/restic_password" = {
        sopsFile = ./secrets/kite-backup.yaml;
        key = "restic_password";
      };
      "kite-backup/b2_account_id" = {
        sopsFile = ./secrets/kite-backup.yaml;
        key = "b2_account_id";
      };
      "kite-backup/b2_account_key" = {
        sopsFile = ./secrets/kite-backup.yaml;
        key = "b2_account_key";
      };
    };

    sops.templates."kite-backup-restic.env" = {
      owner = "root";
      group = "root";
      mode = "0400";
      content = ''
        RESTIC_REPOSITORY=${config.sops.placeholder."kite-backup/restic_repository"}
        RESTIC_PASSWORD=${config.sops.placeholder."kite-backup/restic_password"}
        B2_ACCOUNT_ID=${config.sops.placeholder."kite-backup/b2_account_id"}
        B2_ACCOUNT_KEY=${config.sops.placeholder."kite-backup/b2_account_key"}
      '';
    };

    # Fourth remains responsible for pulling the local recovery copy. This
    # module only moves the independent /data/full off-site archive to Kite.
    services.restic.backups.kite-full = {
      paths = [ "/data/full" ];
      environmentFile = config.sops.templates."kite-backup-restic.env".path;
      initialize = true;
      pruneOpts = [
        "--keep-last 3"
        "--keep-daily 7"
        "--keep-weekly 5"
        "--keep-monthly 12"
      ];
      timerConfig = {
        OnCalendar = "*-*-* 09:30:00 Europe/London";
        Persistent = true;
        RandomizedDelaySec = "30m";
      };
    };

    services.restic.backups.kite-full-check = {
      paths = [ ];
      environmentFile = config.sops.templates."kite-backup-restic.env".path;
      checkOpts = [ "--read-data-subset=10%" ];
      timerConfig = {
        OnCalendar = "Wed *-*-* 05:15:00 Europe/London";
        Persistent = true;
        RandomizedDelaySec = "30m";
      };
    };
  };
}
