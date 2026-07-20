{ config, lib, pkgs, ... }:

let
  dbName = "wantlist";
  role = "wantlist";
  passwordFile = "/var/lib/postgresql/wantlist-db-password";
  psql = "${config.services.postgresql.package}/bin/psql";
in
{
  # Database for the wantlist music app. The app runs in Docker on blink and connects here over
  # the tailnet; only its Postgres lives on partridge. Postgres already listens on all interfaces
  # (see scheduler-db.nix) — this adds the login role, its pg_hba rules and a password. The role
  # OWNS its database so the app can run its own Alembic migrations. Password is generated on-host
  # (like scheduler-db); read it off partridge for the app's .env:
  #   sudo cat /var/lib/postgresql/wantlist-db-password
  services.postgresql.ensureDatabases = [ dbName ];
  services.postgresql.ensureUsers = [
    {
      name = role;
      ensureDBOwnership = true;
    }
  ];

  # Tailnet only (Tailscale CGNAT range + IPv6 ULA). Appended after the base rules in
  # scheduler-db.nix — services.postgresql.authentication is `types.lines`, so it concatenates.
  services.postgresql.authentication = lib.mkAfter ''
    host ${dbName} ${role} 100.64.0.0/10 scram-sha-256
    host ${dbName} ${role} fd7a:115c:a1e0::/48 scram-sha-256
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
