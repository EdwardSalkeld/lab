{ config, exerciseTrackerPackage, ... }:

let
  user = "exercise_tracker";
  group = user;
  grafanaRole = "grafana";
  dbName = "exercise_tracker";
  domain = "exercise-tracker.int.alcachofa.faith";
  port = 8081;
  psql = "${config.services.postgresql.package}/bin/psql";
in
{
  sops.secrets."exercise-tracker/hevy_api_key" = {
    sopsFile = ./secrets/exercise-tracker-hevy-sync.yaml;
    key = "hevy_api_key";
    owner = user;
    inherit group;
  };

  sops.templates."exercise-tracker-hevy-sync.env" = {
    owner = user;
    inherit group;
    mode = "0400";
    content = ''
      EXERCISE_TRACKER_HEVY_API_KEY=${config.sops.placeholder."exercise-tracker/hevy_api_key"}
    '';
  };

  alcachofa.partridge.reverseProxy.routes.${domain}.port = port;

  users.groups.${group} = { };
  users.users.${user} = {
    isSystemUser = true;
    inherit group;
  };

  services.postgresql.ensureDatabases = [ dbName ];
  services.postgresql.ensureUsers = [
    { name = user; }
  ];

  systemd.services.exercise-tracker-db-setup = {
    description = "Apply exercise-tracker migrations and grant access";
    after = [
      "postgresql.service"
      "postgresql-setup.service"
    ];
    requires = [
      "postgresql.service"
      "postgresql-setup.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      Group = "postgres";
    };
    # exercise-tracker owns its database, so CONNECT on it and USAGE on its
    # public schema already come from PUBLIC by default; only table and sequence
    # privileges need granting. The migrations are idempotent, so re-running the
    # loop on every activation is safe. Grafana reads this database for the
    # Fitness dashboard, so the grafana role gets read-only access too.
    script = ''
      for migration in ${exerciseTrackerPackage}/share/exercise-tracker/sql/migrations/*.sql; do
        ${psql} -v ON_ERROR_STOP=1 --dbname=${dbName} -f "$migration"
      done

      ${psql} -v ON_ERROR_STOP=1 --dbname=${dbName} <<'SQL'
      GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ${user};
      GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO ${user};
      ALTER DEFAULT PRIVILEGES IN SCHEMA public
        GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${user};
      ALTER DEFAULT PRIVILEGES IN SCHEMA public
        GRANT USAGE, SELECT ON SEQUENCES TO ${user};

      GRANT SELECT ON ALL TABLES IN SCHEMA public TO ${grafanaRole};
      ALTER DEFAULT PRIVILEGES IN SCHEMA public
        GRANT SELECT ON TABLES TO ${grafanaRole};
SQL
    '';
  };

  systemd.services.exercise-tracker = {
    description = "Exercise tracker HTTP service";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "postgresql.service"
      "exercise-tracker-db-setup.service"
    ];
    requires = [ "exercise-tracker-db-setup.service" ];
    environment = {
      EXERCISE_TRACKER_DATABASE_URL = "postgresql:///${dbName}?host=/run/postgresql&user=${user}&sslmode=disable";
      EXERCISE_TRACKER_LISTEN_ADDR = "127.0.0.1:${toString port}";
    };
    serviceConfig = {
      User = user;
      Group = group;
      ExecStart = "${exerciseTrackerPackage}/bin/exercise-tracker";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  systemd.services.exercise-tracker-hevy-sync = {
    description = "Sync Hevy workouts into exercise-tracker";
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "postgresql.service"
      "exercise-tracker-db-setup.service"
    ];
    requires = [ "exercise-tracker-db-setup.service" ];
    environment = {
      EXERCISE_TRACKER_DATABASE_URL = "postgresql:///${dbName}?host=/run/postgresql&user=${user}&sslmode=disable";
    };
    serviceConfig = {
      Type = "oneshot";
      User = user;
      Group = group;
      EnvironmentFile = config.sops.templates."exercise-tracker-hevy-sync.env".path;
      ExecStart = "${exerciseTrackerPackage}/bin/exercise-tracker sync-hevy";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
    };
  };

  systemd.timers.exercise-tracker-hevy-sync = {
    description = "Daily Hevy workout sync";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 07:15:00";
      Persistent = true;
      RandomizedDelaySec = "20m";
      Unit = "exercise-tracker-hevy-sync.service";
    };
  };
}
