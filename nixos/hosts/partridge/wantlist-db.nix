{ config, lib, pkgs, ... }:

let
  dbName = "wantlist";
  role = "wantlist";
  lanCidr = "10.4.1.0/24";
  lanInterface = "ens18";
  passwordFile = "/var/lib/postgresql/wantlist-db-password";
  psql = "${config.services.postgresql.package}/bin/psql";
in
{
  # Database for the wantlist music app. The app runs in Docker on blink and connects here over
  # the LAN; only its Postgres lives on partridge. Postgres already listens on all interfaces
  # (see scheduler-db.nix) — this adds the login role, its LAN-only pg_hba rule and a password.
  # The role OWNS its database so the app can run its own Alembic migrations. Password is
  # generated on-host (like scheduler-db); read it off partridge for the app's .env:
  #   sudo cat /var/lib/postgresql/wantlist-db-password
  services.postgresql.ensureDatabases = [ dbName ];
  services.postgresql.ensureUsers = [
    {
      name = role;
      ensureDBOwnership = true;
    }
  ];

  # LAN-facing only, not the tailnet: open 5432 on the LAN interface (mirrors postgres-readonly)
  # and restrict this role to the LAN subnet at the pg_hba layer. Postgres rejects any wantlist
  # connection without a matching rule, so tailnet clients can't reach this database even though
  # tailscale0 is a trusted interface. Appended after the base rules in scheduler-db.nix.
  networking.firewall.interfaces.${lanInterface}.allowedTCPPorts = [ 5432 ];
  services.postgresql.authentication = lib.mkAfter ''
    host ${dbName} ${role} ${lanCidr} scram-sha-256
  '';

  system.activationScripts.wantlistDbPassword.text = ''
    install -d -m 0700 -o postgres -g postgres /var/lib/postgresql
    if [ ! -s ${passwordFile} ]; then
      umask 077
      ${pkgs.openssl}/bin/openssl rand -base64 36 > ${passwordFile}
    fi
    chown postgres:postgres ${passwordFile}
    chmod 0400 ${passwordFile}
  '';

  systemd.services.wantlist-db-setup = {
    description = "Configure the wantlist database role password";
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
      db_password="$(tr -d '\n' < ${passwordFile})"
      ${psql} -v ON_ERROR_STOP=1 --set=db_password="$db_password" --dbname=postgres <<'SQL'
      ALTER ROLE ${role} WITH LOGIN PASSWORD :'db_password';
      SQL
    '';
  };
}
