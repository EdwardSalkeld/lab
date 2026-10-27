{
  config,
  lib,
  ...
}:
let
  secretNames = [
    "postgres_password"
    "secret_key"
    "avatar_salt"
    "shared_secret"
    "camo_key"
    "rabbitmq_password"
    "memcached_password"
    "redis_password"
  ];
  psql = "${config.services.postgresql.package}/bin/psql";
in
{
  # The application is a dedicated Debian guest on Luna. Keep durable state
  # here so postgresqlBackup.backupAll and the existing Restic job cover it.
  sops.secrets = lib.genAttrs (map (name: "zulip/${name}") secretNames) (name: {
    sopsFile = ./secrets/zulip.yaml;
    key = lib.removePrefix "zulip/" name;
    owner = if name == "zulip/postgres_password" then "postgres" else "root";
    group = if name == "zulip/postgres_password" then "postgres" else "root";
    restartUnits = lib.optional (name == "zulip/postgres_password") "zulip-db-setup.service";
  });
  # Stable application identities are encrypted in Git, not generated only on
  # the disposable app disk. SMTP reuses the existing Fastmail app credential.
  sops.templates."zulip-secrets.conf" = {
    owner = "root";
    group = "root";
    mode = "0400";
    content =
      "[secrets]\n"
      + lib.concatMapStringsSep "\n" (
        name: "${name} = ${config.sops.placeholder."zulip/${name}"}"
      ) secretNames
      + "\nemail_password = ${config.sops.placeholder."grafana/smtp_password"}\n";
  };

  services.postgresql.ensureUsers = [ { name = "zulip"; } ];
  networking.firewall.interfaces.ens18.allowedTCPPorts = [ 5432 ];
  services.postgresql.authentication = lib.mkAfter ''
    host zulip zulip 10.4.1.0/24 scram-sha-256
  '';
  systemd.services.zulip-db-setup = {
    description = "Create Zulip's database and login on the backed-up cluster";
    after = [ "postgresql-setup.service" ];
    requires = [ "postgresql-setup.service" ];
    before = [ "postgresqlBackup.service" ];
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [ config.sops.secrets."zulip/postgres_password".path ];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      Group = "postgres";
    };
    script = ''
      password="$(tr -d '\n' < ${config.sops.secrets."zulip/postgres_password".path})"
      ${psql} --dbname=postgres -v ON_ERROR_STOP=1 --set=password="$password" <<'SQL'
      ALTER ROLE zulip WITH LOGIN PASSWORD :'password';
      SELECT $create$CREATE DATABASE zulip OWNER zulip ENCODING 'UTF8' LC_COLLATE 'C.UTF-8' LC_CTYPE 'C.UTF-8' TEMPLATE template0$create$
      WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'zulip')
      \gexec
      SQL
    '';
  };

  alcachofa.partridge.reverseProxy.routes."zulip.int.alcachofa.faith" = {
    # Resolve lazily: Partridge can deploy before the guest/DHCP record exists.
    host = "$zulip_upstream";
    port = 80;
    allowedCIDRs = [
      "10.4.1.0/24"
      "100.64.0.0/10"
    ];
  };
  services.nginx.virtualHosts."zulip.int.alcachofa.faith" = {
    extraConfig = "client_max_body_size 25m;";
    locations."/".extraConfig = lib.mkAfter ''
      resolver 10.4.1.1 valid=30s;
      set $zulip_upstream zulip-vm.int.alcachofa.faith;
      proxy_read_timeout 1200s;
      proxy_buffering off;
    '';
  };
}
