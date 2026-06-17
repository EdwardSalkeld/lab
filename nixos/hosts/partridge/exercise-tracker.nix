{ config, exerciseTrackerPackage, ... }:

let
  user = "exercise_tracker";
  group = user;
  dbName = "exercise_tracker";
  domain = "exercise-tracker.int.alcachofa.faith";
  port = 8081;
  psql = "${config.services.postgresql.package}/bin/psql";
in
{
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
    description = "Configure PostgreSQL access and schema for exercise-tracker";
    after = [
      "postgresql.service"
      "postgresql-setup.service"
      "scheduler-db-setup.service"
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
    script = ''
      ${psql} -v ON_ERROR_STOP=1 --dbname=postgres <<'SQL'
      GRANT CONNECT ON DATABASE ${dbName} TO ${user};
SQL

      for migration in ${exerciseTrackerPackage}/share/exercise-tracker/sql/migrations/*.sql; do
        ${psql} -v ON_ERROR_STOP=1 --dbname=${dbName} -f "$migration"
      done

      ${psql} -v ON_ERROR_STOP=1 --dbname=${dbName} <<'SQL'
      GRANT USAGE ON SCHEMA public TO ${user};
      GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ${user};
      GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO ${user};
      ALTER DEFAULT PRIVILEGES IN SCHEMA public
        GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${user};
      ALTER DEFAULT PRIVILEGES IN SCHEMA public
        GRANT USAGE, SELECT ON SEQUENCES TO ${user};
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
}
