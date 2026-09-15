{ config, ... }:

{
  sops.secrets = {
    "postgres-backup/restic_repository" = {
      sopsFile = ./secrets/postgres-backup.yaml;
      key = "restic_repository";
      owner = "root";
      group = "root";
    };
    "postgres-backup/restic_password" = {
      sopsFile = ./secrets/postgres-backup.yaml;
      key = "restic_password";
      owner = "root";
      group = "root";
    };
    "postgres-backup/b2_account_id" = {
      sopsFile = ./secrets/postgres-backup.yaml;
      key = "b2_account_id";
      owner = "root";
      group = "root";
    };
    "postgres-backup/b2_account_key" = {
      sopsFile = ./secrets/postgres-backup.yaml;
      key = "b2_account_key";
      owner = "root";
      group = "root";
    };
  };

  sops.templates."postgres-backup-restic.env" = {
    owner = "root";
    group = "root";
    mode = "0400";
    content = ''
      RESTIC_REPOSITORY=${config.sops.placeholder."postgres-backup/restic_repository"}
      RESTIC_PASSWORD=${config.sops.placeholder."postgres-backup/restic_password"}
      B2_ACCOUNT_ID=${config.sops.placeholder."postgres-backup/b2_account_id"}
      B2_ACCOUNT_KEY=${config.sops.placeholder."postgres-backup/b2_account_key"}
    '';
  };

  services.postgresqlBackup = {
    enable = true;
    backupAll = true;
    compression = "zstd";
    compressionLevel = 6;
    location = "/var/backup/postgresql";
    startAt = "*-*-* 02:00:00";
  };

  services.restic.backups = {
    partridge-postgres = {
      paths = [ "/var/backup/postgresql" ];
      environmentFile = config.sops.templates."postgres-backup-restic.env".path;
      initialize = true;
      pruneOpts = [
        "--keep-daily 3"
        "--keep-weekly 4"
      ];
      timerConfig = {
        OnCalendar = "*-*-* 03:00:00";
        Persistent = true;
        RandomizedDelaySec = "30m";
      };
    };

    partridge-postgres-check = {
      paths = [ ];
      environmentFile = config.sops.templates."postgres-backup-restic.env".path;
      checkOpts = [ "--read-data-subset=10%" ];
      timerConfig = {
        OnCalendar = "Wed *-*-* 05:15:00";
        Persistent = true;
        RandomizedDelaySec = "30m";
      };
    };
  };

  systemd.services.restic-backups-partridge-postgres.after = [
    "postgresqlBackup.service"
  ];

  systemd.timers.postgresqlBackup.timerConfig.Persistent = true;
}
