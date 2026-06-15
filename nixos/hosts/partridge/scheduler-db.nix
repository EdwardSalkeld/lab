{ config, pkgs, ... }:

let
  dbName = "scheduler";
  writerRole = "scheduler_writer";
  writerPasswordFile = "/var/lib/postgresql/scheduler-db-writer-password";
  psql = "${config.services.postgresql.package}/bin/psql";
in
{
  services.postgresql = {
    enable = true;

    ensureDatabases = [ dbName ];
    ensureUsers = [
      { name = writerRole; }
    ];

    settings = {
      listen_addresses = "*";
      password_encryption = "scram-sha-256";
    };

    authentication = ''
      local all all peer
      host ${dbName} ${writerRole} 100.64.0.0/10 scram-sha-256
      host ${dbName} ${writerRole} fd7a:115c:a1e0::/48 scram-sha-256
    '';
  };

  system.activationScripts.schedulerDbWriterPassword.text = ''
    install -d -m 0700 -o postgres -g postgres /var/lib/postgresql
    if [ ! -s ${writerPasswordFile} ]; then
      umask 077
      ${pkgs.openssl}/bin/openssl rand -base64 36 > ${writerPasswordFile}
    fi
    chown postgres:postgres ${writerPasswordFile}
    chmod 0400 ${writerPasswordFile}
  '';

  systemd.services.postgresql.postStart = ''
    writer_password="$(tr -d '\n' < ${writerPasswordFile})"

    ${psql} -v ON_ERROR_STOP=1 --set=writer_password="$writer_password" --dbname=postgres <<'SQL'
    ALTER ROLE ${writerRole} WITH LOGIN PASSWORD :'writer_password';
    GRANT CONNECT ON DATABASE ${dbName} TO ${writerRole};
    GRANT CONNECT ON DATABASE ${dbName} TO grafana;
SQL
  '';
}
