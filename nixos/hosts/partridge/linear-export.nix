{ config, pkgs, linearExportPackage, ... }:

let
  user = "linearexport";
  group = "linearexport";
  dbName = "scheduler";
  psql = "${config.services.postgresql.package}/bin/psql";
in
{
  sops.secrets."linear-export/linear_api_key" = {
    sopsFile = ./secrets/linear-export.yaml;
    key = "linear_api_key";
    owner = user;
    inherit group;
  };

  sops.templates."linear-export.env" = {
    owner = user;
    inherit group;
    mode = "0400";
    content = ''
      LINEAR_API_KEY=${config.sops.placeholder."linear-export/linear_api_key"}
    '';
  };

  users.groups.${group} = { };
  users.users.${user} = {
    isSystemUser = true;
    inherit group;
  };

  # linear-export connects to PostgreSQL over the local socket using peer
  # authentication, so the OS user name must match a PostgreSQL role.
  services.postgresql.ensureUsers = [
    { name = user; }
  ];

  systemd.services.linear-export-db-setup = {
    description = "Create the linear_issues table and grant linear-export access";
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
    # Only table-level privileges are granted: CONNECT on the database and
    # USAGE on the public schema are already held by PUBLIC by default, and
    # granting them per role rewrites shared catalog rows (pg_database, the
    # public pg_namespace) that other db-setup units also touch — the source of
    # the "tuple concurrently updated" race. A per-table grant touches only this
    # table's row, so no ordering against the other units is needed.
    script = ''
      ${psql} -v ON_ERROR_STOP=1 --dbname=${dbName} <<'SQL'
      CREATE TABLE IF NOT EXISTS linear_issues (
        id          text PRIMARY KEY,
        title       text,
        status      text,
        project     text,
        cycle       text,
        description text,
        labels      jsonb,
        comments    jsonb,
        history     jsonb,
        created_at  timestamptz,
        updated_at  timestamptz
      );
      GRANT SELECT, INSERT, UPDATE ON TABLE linear_issues TO ${user};
SQL
    '';
  };

  systemd.services.linear-export = {
    description = "Export Linear issues to Postgres";
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "postgresql.service"
      "linear-export-db-setup.service"
    ];
    requires = [ "linear-export-db-setup.service" ];
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
      EnvironmentFile = config.sops.templates."linear-export.env".path;
      ExecStart = "${linearExportPackage}/bin/linear-export";
      NoNewPrivileges = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      PrivateTmp = true;
    };
  };

  systemd.timers.linear-export = {
    description = "Daily Linear issue export";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:30:00";
      Persistent = true;
      RandomizedDelaySec = "20m";
      Unit = "linear-export.service";
    };
  };
}
