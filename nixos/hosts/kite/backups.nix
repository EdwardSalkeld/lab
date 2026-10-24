{ config, lib, pkgs, ... }:

let
  cfg = config.alcachofa.kite.backups;
  environmentFile = config.sops.templates."kite-backup-restic.env".path;
  # Preserve the existing archive identity used by Fourth's Docker container.
  # This is a logical dataset name; journal logs still identify the real host.
  archiveHost = "docker";
  archivePath = "/mnt/volumes";
  guard = {
    unitConfig.RequiresMountsFor = [ "/data" ];
    unitConfig.AssertPathIsMountPoint = "/data";
  };
in
{
  options.alcachofa.kite.backups = {
    enable = lib.mkEnableOption "Kite's off-site data backup";
  };

  config = lib.mkIf cfg.enable {
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
      # The private, read-only bind below exposes /data/full under the same
      # path as the old container so parent selection and retention continue.
      paths = [ archivePath ];
      inherit environmentFile;
      initialize = false;
      extraBackupArgs = [ "--host=${archiveHost}" "--tag=dataplan" "--verbose" ];
      exclude = [ "*.tmp" ];
      timerConfig = {
        OnCalendar = "Mon *-*-* 06:30:00 Europe/London";
        Persistent = true;
      };
    };

    services.restic.backups.kite-full-prune = {
      paths = [ ];
      inherit environmentFile;
      pruneOpts = [
        "--host ${archiveHost}"
        "--path ${archivePath}"
        "--tag dataplan"
        "--keep-last 3"
        "--keep-daily 7"
        "--keep-weekly 5"
        "--keep-monthly 12"
      ];
      timerConfig = {
        OnCalendar = "Tue *-*-* 04:00:00 Europe/London";
        # Never run catch-up pruning at the initial migration activation.
        Persistent = false;
      };
    };

    services.restic.backups.kite-full-check = {
      paths = [ ];
      inherit environmentFile;
      checkOpts = [ "--read-data-subset=10%" ];
      timerConfig = {
        OnCalendar = "Wed *-*-* 05:15:00 Europe/London";
        Persistent = true;
      };
    };

    systemd.services.restic-backups-kite-full = lib.recursiveUpdate guard {
      serviceConfig = {
        BindReadOnlyPaths = [ "/data/full:${archivePath}" ];
        ExecStartPre = pkgs.writeShellScript "kite-backup-start" ''
          date +%s > /run/restic-backups-kite-full/started
        '';
        # Only emit this marker after a successful backup. Reuse the existing
        # log format so the dashboard can show both sides of the hand-off.
        ExecStartPost = pkgs.writeShellScript "kite-backup-complete" ''
          started=$(cat /run/restic-backups-kite-full/started)
          duration=$(( $(date +%s) - started ))
          echo "Finished backup at $(date --iso-8601=seconds) after $duration seconds"
          touch /var/lib/kite-backup/verified
        '';
        StateDirectory = "kite-backup";
      };
    };
    # Keep a newly installed host from expiring snapshots until it has
    # successfully backed up to the existing repository at least once.
    systemd.services.restic-backups-kite-full-prune = {
      unitConfig.ConditionPathExists = "/var/lib/kite-backup/verified";
    };
  };
}
