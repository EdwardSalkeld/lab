{ config, pkgs, octopusDlPackage, ... }:

let
  user = "octopusdl";
  group = "octopusdl";
  dbName = "scheduler";
  psql = "${config.services.postgresql.package}/bin/psql";
in
{
  sops.secrets."octopus-dl/octopus_api_key" = {
    sopsFile = ./secrets/octopus-dl.yaml;
    key = "octopus_api_key";
    owner = user;
    inherit group;
  };

  sops.templates."octopus-dl.env" = {
    owner = user;
    inherit group;
    mode = "0400";
    content = ''
      OCTOPUS_API_KEY=${config.sops.placeholder."octopus-dl/octopus_api_key"}
    '';
  };

  users.groups.${group} = { };
  users.users.${user} = {
    isSystemUser = true;
    inherit group;
  };

  # octopus-dl connects to PostgreSQL over the local socket using peer
  # authentication, so the OS user name must match a PostgreSQL role.
  services.postgresql.ensureUsers = [
    { name = user; }
  ];

  systemd.services.octopus-dl-db-setup = {
    description = "Grant octopus-dl access to the scheduler usages table";
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
    script = ''
      ${psql} -v ON_ERROR_STOP=1 --dbname=postgres <<'SQL'
      GRANT CONNECT ON DATABASE ${dbName} TO ${user};
SQL

      ${psql} -v ON_ERROR_STOP=1 --dbname=${dbName} <<'SQL'
      CREATE TABLE IF NOT EXISTS usages (
        consumption double precision NOT NULL,
        interval_start timestamptz NOT NULL,
        interval_end timestamptz NOT NULL,
        usage_type text NOT NULL,
        PRIMARY KEY (interval_start, usage_type)
      );
      GRANT USAGE ON SCHEMA public TO ${user};
      GRANT SELECT, INSERT, UPDATE ON TABLE usages TO ${user};
SQL
    '';
  };

  systemd.services.octopus-dl = {
    description = "Download Octopus Energy consumption data";
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "postgresql.service"
      "octopus-dl-db-setup.service"
    ];
    requires = [ "octopus-dl-db-setup.service" ];
    environment = {
      DB_HOST = "/run/postgresql";
      DB_PORT = "5432";
      DB_USER = user;
      DB_NAME = dbName;
      DB_SSLMODE = "disable";
    };
    serviceConfig = {
      Type = "oneshot";
      User = user;
      Group = group;
      EnvironmentFile = config.sops.templates."octopus-dl.env".path;
      ExecStart = "${octopusDlPackage}/bin/octopus-dl";
      NoNewPrivileges = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      PrivateTmp = true;
    };
  };

  systemd.timers.octopus-dl = {
    description = "Daily Octopus Energy consumption download";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:00:00";
      Persistent = true;
      RandomizedDelaySec = "20m";
      Unit = "octopus-dl.service";
    };
  };
}
