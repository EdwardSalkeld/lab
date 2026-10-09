{ config, pkgs, ... }:

let
  stateDir = "/var/lib/webtrees";
  source = pkgs.fetchzip {
    url = "https://github.com/fisharebest/webtrees/releases/download/2.2.6/webtrees-2.2.6.zip";
    hash = "sha256-9DI86LOADdaEbwR3L/3/xuXvrSL96DYAkNdzpQ7b9OU=";
  };
  # Keep PHP code immutable; only data (including media/config) is writable.
  webtrees = pkgs.runCommand "webtrees-2.2.6" { } ''
    mkdir -p "$out"
    cp -R ${source}/. "$out/"
    chmod -R u+w "$out"
    rm -r "$out/data"
    ln -s ${stateDir}/data "$out/data"
  '';
  php = pkgs.php84.buildEnv {
    extensions =
      { enabled, all }:
      enabled
      ++ [
        all.pdo_pgsql
        all.gd
        all.intl
        all.zip
      ];
  };
in
{
  users.groups.webtrees = { };
  users.users.webtrees = {
    isSystemUser = true;
    group = "webtrees";
    home = stateDir;
  };

  # Local peer authentication uses the PHP worker's Unix identity. No new
  # database password, TCP listener or credentials handoff is needed.
  # Do not add this application's provisioning to postgresql-setup: existing
  # services such as Forgejo require that shared unit. A webtrees setup error
  # must fail only webtrees. Ordering after shared setup avoids catalog races.
  systemd.services.webtrees-db-setup = {
    description = "Provision the webtrees database independently";
    after = [ "postgresql.service" "postgresql-setup.service" ];
    requires = [ "postgresql.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "postgres";
      Group = "postgres";
    };
    path = [ config.services.postgresql.finalPackage ];
    environment.PGPORT = toString config.services.postgresql.settings.port;
    script = ''
      psql -X -v ON_ERROR_STOP=1 --dbname=postgres <<'SQL'
      SELECT 'CREATE ROLE webtrees LOGIN'
      WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'webtrees')
      \gexec
      SELECT 'CREATE DATABASE webtrees OWNER webtrees'
      WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'webtrees')
      \gexec
      ALTER DATABASE webtrees OWNER TO webtrees;
      SQL
    '';
  };

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0700 webtrees webtrees -"
    "d ${stateDir}/data 0700 webtrees webtrees -"
    "d ${stateDir}/sessions 0700 webtrees webtrees -"
  ];

  services.phpfpm.pools.webtrees = {
    user = "webtrees";
    group = "webtrees";
    phpPackage = php;
    settings = {
      "listen.owner" = config.services.nginx.user;
      "listen.group" = config.services.nginx.group;
      "listen.mode" = "0600";
      # Occasional use: no PHP request workers remain between visits.
      pm = "ondemand";
      "pm.max_children" = 2;
      "pm.process_idle_timeout" = "30s";
      "pm.max_requests" = 100;
      "request_terminate_timeout" = "300s";
    };
    phpOptions = ''
      memory_limit = 256M
      upload_max_filesize = 100M
      post_max_size = 110M
      max_execution_time = 300
      session.save_path = ${stateDir}/sessions
      expose_php = Off
    '';
  };
  systemd.services.phpfpm-webtrees = {
    after = [
      "postgresql.service"
      "webtrees-db-setup.service"
    ];
    requires = [
      "postgresql.service"
      "webtrees-db-setup.service"
    ];
    preStart = ''
      # Seed the upstream data skeleton once; preserve settings and uploads.
      if [ ! -e ${stateDir}/data/index.php ]; then
        cp -R ${source}/data/. ${stateDir}/data/
        chown -R webtrees:webtrees ${stateDir}/data
        chmod -R u+rwX,go-rwx ${stateDir}/data
      fi
    '';
  };

  # Separate LAN/tailnet port lets both candidate PRs coexist. Wildcard
  # listeners avoid depending on Tailscale assigning its addresses at boot;
  # the source allowlist below and host firewall restrict access.
  networking.firewall.interfaces.ens18.allowedTCPPorts = [ 5052 ];
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 5052 ];
  services.nginx.virtualHosts."webtrees-lan" = {
    listen = [
      {
        addr = "0.0.0.0";
        port = 5052;
      }
      {
        addr = "[::]";
        port = 5052;
      }
    ];
    root = webtrees;
    extraConfig = ''
      index index.php;
      allow 10.4.1.0/24;
      allow 100.64.0.0/10;
      allow fd7a:115c:a1e0::/48;
      deny all;
      client_max_body_size 110m;
    '';
    locations."/".tryFiles = "$uri $uri/ /index.php?$query_string";
    # Nginx does not read Apache's .htaccess. Explicitly block all private
    # directories, including configuration, GEDCOM uploads and raw media.
    locations."~ ^/(data|app|resources|vendor)(/|$)".extraConfig = "deny all;";
    locations."~ /\\.".extraConfig = "deny all;";
    locations."= /index.php" = {
      fastcgiParams.SCRIPT_FILENAME = "${webtrees}/index.php";
      extraConfig = ''
        include ${pkgs.nginx}/conf/fastcgi_params;
        fastcgi_pass unix:${config.services.phpfpm.pools.webtrees.socket};
        fastcgi_read_timeout 300s;
      '';
    };
    locations."~ \\.php$".extraConfig = "deny all;";
  };

  # Existing all-database SQL dump includes webtrees. Media and config need
  # the existing encrypted off-host file backup as well.
  services.restic.backups.partridge-postgres.paths = [ "${stateDir}/data" ];
}
