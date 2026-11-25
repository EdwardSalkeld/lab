{ config, ... }:

let
  forgejoDomain = "code.alcachofa.faith";
  forgejoPort = 3000;
  stateDir = config.services.forgejo.stateDir;
in
{
  alcachofa.partridge.reverseProxy.routes.${forgejoDomain}.port = forgejoPort;

  # Forgejo git SSH (built-in server on 2222, configured below).
  networking.firewall.allowedTCPPorts = [ 2222 ];

  services.forgejo = {
    enable = true;
    database.type = "postgres";
    lfs.enable = true;
    stateDir = "/srv/code/forgejo";
    useWizard = false;

    settings = {
      server = {
        DOMAIN = forgejoDomain;
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = forgejoPort;
        ROOT_URL = "https://${forgejoDomain}/";

        DISABLE_SSH = false;
        START_SSH_SERVER = true;
        SSH_DOMAIN = forgejoDomain;
        SSH_PORT = 2222;
        SSH_LISTEN_PORT = 2222;
        SSH_USER = "git";
        # Without this the built-in server only accepts the run user (forgejo),
        # so the git@ clone URL the web UI shows is rejected.
        BUILTIN_SSH_SERVER_USER = "git";
      };

      service = {
        DISABLE_REGISTRATION = true;
        REQUIRE_SIGNIN_VIEW = true;
      };

      actions = {
        ENABLED = true;
        # Resolve `uses:` actions (actions/checkout@v4 etc.) from GitHub, since
        # private repos moving onto this Forgejo will reference them.
        DEFAULT_ACTIONS_URL = "github";
      };
    };
  };

  # Repositories, LFS objects, attachments and custom/conf (SECRET_KEY, which
  # decrypts 2FA secrets in Postgres) live only on this disk; the database is
  # covered by partridge-postgres. This shares that job's B2 repository.
  services.restic.backups.partridge-forgejo = {
    paths = [ stateDir ];
    exclude = [
      "${stateDir}/log"
      "${stateDir}/data/tmp"
      "${stateDir}/data/queues"
      "${stateDir}/data/indexers"
      "${stateDir}/data/sessions"
      "${stateDir}/data/repo-archive"
    ];
    environmentFile = config.sops.templates."postgres-backup-restic.env".path;
    # Wait out the exclusive locks of partridge-postgres's prune and the
    # weekly check instead of failing.
    extraBackupArgs = [ "--retry-lock 1h" ];
    # No pruneOpts: partridge-postgres's `forget` has no --host/--path filter,
    # so its keep policy already applies to this job's snapshot group too.
    # A second, different policy here would make the stricter one win for both.
    backupPrepareCommand = "systemctl stop forgejo.service";
    backupCleanupCommand = "systemctl start forgejo.service";
    timerConfig = {
      OnCalendar = "*-*-* 04:00:00";
      Persistent = true;
      RandomizedDelaySec = "15m";
    };
  };

  systemd.services.restic-backups-partridge-forgejo.after = [
    "restic-backups-partridge-postgres.service"
  ];
}
