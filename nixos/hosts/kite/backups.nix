{ config, lib, pkgs, ... }:

let
  cfg = config.alcachofa.kite.backups;
  fourthSshKey = config.sops.secrets."kite-backup/fourth_ssh_key".path;
  fourthKnownHosts = config.sops.secrets."kite-backup/fourth_known_hosts".path;
in
{
  options.alcachofa.kite.backups = {
    enable = lib.mkEnableOption "Kite's on-site and off-site data backups";

    fourthTarget = lib.mkOption {
      type = lib.types.str;
      default = "kite-backup@fourth.ts.alcachofa.faith";
      description = "Restricted SSH account on Fourth that receives Kite's data copies.";
    };
  };

  config = lib.mkIf cfg.enable {
    # The first deployment needs these six values copied from Fourth's ignored
    # Docker environment file, plus a dedicated key for the restricted Fourth
    # receive account.  The accompanying .example file documents every value.
    sops.secrets = {
      "kite-backup/fourth_ssh_key" = {
        sopsFile = ./secrets/kite-backup.yaml;
        key = "fourth_ssh_key";
        owner = "edward";
        group = "data";
        mode = "0400";
      };
      "kite-backup/fourth_known_hosts" = {
        sopsFile = ./secrets/kite-backup.yaml;
        key = "fourth_known_hosts";
        owner = "edward";
        group = "data";
        mode = "0400";
      };
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

    systemd.services.kite-data-sync = {
      description = "Push Kite full and partial data copies to Fourth";
      after = [ "data.mount" "network-online.target" ];
      wants = [ "network-online.target" ];
      unitConfig.ConditionPathIsMountPoint = "/data";
      path = [ pkgs.coreutils pkgs.openssh pkgs.rsync ];
      serviceConfig = {
        Type = "oneshot";
        User = "edward";
        Group = "data";
        UMask = "0027";
        Nice = 10;
        IOSchedulingClass = "idle";
      };
      script = ''
        set -euo pipefail

        ssh_command="${pkgs.openssh}/bin/ssh -i ${fourthSshKey} -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=${fourthKnownHosts}"
        sync_dir() {
          source=$1
          destination=$2
          echo "Starting Kite to Fourth sync: $source -> $destination"
          ${pkgs.rsync}/bin/rsync -aiv --delete-delay \
            --exclude='lost+found' \
            --exclude='blink-reinstall-backup-20260829T080849Z/' \
            --exclude='*/venv/*' \
            --exclude='**/mysql/scheduler' \
            -e "$ssh_command" \
            "$source/" "${cfg.fourthTarget}:$destination/"
          echo "Completed Kite to Fourth sync: $source -> $destination"
        }

        sync_dir /data/full /data/full
        sync_dir /data/partial /data/partial
      '';
    };

    systemd.timers.kite-data-sync = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # Preserve the old Fourth cron's 04:32 Europe/London schedule across
        # BST changes even though NixOS hosts otherwise use UTC by default.
        OnCalendar = "*-*-* 04:32:00 Europe/London";
        Persistent = true;
        RandomizedDelaySec = "15m";
      };
    };

    # This archives only /data/full.  /data/partial deliberately has the local
    # Kite and Fourth copies but no off-site copy, as described in house#120.
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
