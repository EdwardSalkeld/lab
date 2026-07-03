{ config, lib, ... }:

let
  role = "billy_ro";
  # Databases Billy is allowed to read. Deliberately excludes forgejo, grafana
  # and postgres, whose tables hold credential hashes and session tokens.
  readableDbs = [ "scheduler" "exercise_tracker" ];
  lanCidr = "10.4.1.0/24";
  lanInterface = "ens18";
  psql = "${config.services.postgresql.package}/bin/psql";
  secretPath = config.sops.secrets."postgres-readonly/readonly_password".path;
in
{
  sops.secrets."postgres-readonly/readonly_password" = {
    sopsFile = ./secrets/postgres-readonly.yaml;
    key = "readonly_password";
    owner = "postgres";
    group = "postgres";
  };

  services.postgresql.ensureUsers = [
    { name = role; }
  ];

  # Reachable from the LAN (the chatting worker connects over it), not just the
  # tailnet. Postgres already listens on all interfaces; open 5432 only on the
  # LAN interface so it is not exposed on any other link.
  networking.firewall.interfaces.${lanInterface}.allowedTCPPorts = [ 5432 ];

  # Restrict billy_ro at the pg_hba layer to exactly the readable databases from
  # the LAN subnet, as defence in depth on top of the table grants. Appended
  # after the rules defined in scheduler-db.nix.
  services.postgresql.authentication = lib.mkAfter (
    lib.concatMapStringsSep "\n"
      (db: "host ${db} ${role} ${lanCidr} scram-sha-256")
      readableDbs
  );

  systemd.services.postgres-readonly-setup = {
    description = "Configure the ${role} read-only role and grant SELECT on data databases";
    after = [
      "postgresql.service"
      "postgresql-setup.service"
      # Order after the per-database setup units so their tables exist for the
      # initial grant; re-running on every activation catches anything added later.
      "octopus-dl-db-setup.service"
      "exercise-tracker-db-setup.service"
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
    # CONNECT on each database and USAGE on its public schema are already held by
    # PUBLIC, so only table-level SELECT is granted here. That touches only each
    # table's row, avoiding the shared-catalog "tuple concurrently updated" race
    # that per-database grants would introduce against the other db-setup units.
    # Tables in both databases are owned by postgres (this service's user), so a
    # bare ALTER DEFAULT PRIVILEGES covers future tables.
    script = ''
      readonly_password="$(tr -d '\n' < ${secretPath})"

      ${psql} -v ON_ERROR_STOP=1 --set=readonly_password="$readonly_password" --dbname=postgres <<'SQL'
      ALTER ROLE ${role} WITH LOGIN PASSWORD :'readonly_password';
      SQL

    '' + lib.concatMapStringsSep "\n" (db: ''
      ${psql} -v ON_ERROR_STOP=1 --dbname=${db} <<'SQL'
      GRANT SELECT ON ALL TABLES IN SCHEMA public TO ${role};
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO ${role};
      SQL
    '') readableDbs;
  };
}
