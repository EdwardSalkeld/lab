{ config, workoutServicePackage, ... }:

let
  user = "workout_service";
  group = user;
  dbName = "workout_service";
  domain = "workout.int.alcachofa.faith";
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

  systemd.services.workout-service-db-setup = {
    description = "Configure PostgreSQL access and schema for workout-service";
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

      for migration in ${workoutServicePackage}/share/workout-service/sql/migrations/*.sql; do
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

  systemd.services.workout-service = {
    description = "Workout data HTTP service";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "postgresql.service"
      "workout-service-db-setup.service"
    ];
    requires = [ "workout-service-db-setup.service" ];
    environment = {
      WORKOUT_SERVICE_DATABASE_URL = "postgresql:///${dbName}?host=/run/postgresql&user=${user}&sslmode=disable";
      WORKOUT_SERVICE_LISTEN_ADDR = "127.0.0.1:${toString port}";
    };
    serviceConfig = {
      User = user;
      Group = group;
      ExecStart = "${workoutServicePackage}/bin/workout-service";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
