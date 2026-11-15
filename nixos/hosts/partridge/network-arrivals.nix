{ config, pkgs, ... }:
let
  user = "network_arrivals";
  python = pkgs.python3.withPackages (p: [ p.psycopg2 ]);
  source = ../../../tools/network-arrivals;
  settings = pkgs.writeText "network-arrivals.json" (
    builtins.toJSON {
      url = "https://10.4.1.1";
      verify_tls = false; # Same self-signed router certificate as opnsense-exporter.
      database = "dbname=network_inventory user=${user} host=/run/postgresql";
      metrics_path = "/var/lib/network-arrivals/collector.prom";
      zones = {
        trusted = "10.4.1.0/24";
        untrusted = "10.4.20.0/24";
      };
      translated_macs = {
        "c4:e9:84:6e:02:dc" = [ "10.4.1.2" ];
      };
      interfaces = [
        "LAN"
        "UNTRUSTED"
      ];
      friendly_names = { };
    }
  );
  psql = "${config.services.postgresql.package}/bin/psql";
in
{
  # Reuse the encrypted monitoring credential, in a separately owned template.
  # Required OPNsense privileges are granted; see the runbook.
  sops.templates."network-arrivals.env" = {
    owner = user;
    group = user;
    mode = "0400";
    content = ''
      OPNSENSE_API_KEY=${config.sops.placeholder."opnsense-exporter/api_key"}
      OPNSENSE_API_SECRET=${config.sops.placeholder."opnsense-exporter/api_secret"}
    '';
  };
  users.groups.${user} = { };
  users.users.${user} = {
    isSystemUser = true;
    group = user;
  };
  services.postgresql.ensureDatabases = [ "network_inventory" ];
  services.postgresql.ensureUsers = [ { name = user; } ];
  systemd.services.network-arrivals-db-setup = {
    description = "Create network inventory schema and grant local access";
    wantedBy = [ "multi-user.target" ];
    after = [
      "postgresql.service"
      "postgresql-setup.service"
    ];
    requires = [
      "postgresql.service"
      "postgresql-setup.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "postgres";
    };
    script = ''
      ${psql} -v ON_ERROR_STOP=1 -d network_inventory -f ${source}/schema.sql
      ${psql} -v ON_ERROR_STOP=1 -d network_inventory <<'SQL'
      REVOKE ALL ON DATABASE network_inventory FROM PUBLIC;
      GRANT CONNECT ON DATABASE network_inventory TO network_arrivals, grafana;
      REVOKE ALL ON SCHEMA public FROM PUBLIC;
      GRANT USAGE ON SCHEMA public TO network_arrivals, grafana;
      GRANT SELECT,INSERT,UPDATE ON ALL TABLES IN SCHEMA public TO network_arrivals;
      GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA public TO network_arrivals;
      GRANT SELECT ON ALL TABLES IN SCHEMA public TO grafana;
      SQL
    '';
  };
  systemd.services.network-arrivals = {
    description = "Record OPNsense device observations and arrivals";
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "network-arrivals-db-setup.service"
    ];
    requires = [ "network-arrivals-db-setup.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = user;
      Group = user;
      EnvironmentFile = config.sops.templates."network-arrivals.env".path;
      ExecStart = "${python}/bin/python ${source}/collector.py ${settings}";
      StateDirectory = "network-arrivals";
      StateDirectoryMode = "0755"; # node-exporter reads only the aggregate .prom file.
      TimeoutStartSec = "90s";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
      ];
      UMask = "0022";
    };
  };
  systemd.timers.network-arrivals = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "90s";
      OnUnitActiveSec = "60s";
      AccuracySec = "1s";
    };
  };
  services.prometheus.exporters.node = {
    enabledCollectors = [ "textfile" ];
    extraFlags = [ "--collector.textfile.directory=/var/lib/network-arrivals" ];
  };
}
