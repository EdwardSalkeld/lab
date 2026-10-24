{ config, pkgs, ... }:

let
  domain = "freshrss-docker.falcon.alcachofa.faith";
  dataDir = "/var/lib/freshrss";
  backupDir = "/var/backups/freshrss";
in
{
  # FreshRSS state is restored from the pre-NixOS archive. Do not use the
  # services.freshrss module here: its bootstrap unit rewrites the configured
  # default user's password on every activation.
  users.groups.freshrss = { };
  users.users.freshrss = {
    isSystemUser = true;
    group = "freshrss";
    home = dataDir;
  };

  systemd.tmpfiles.settings."10-freshrss"."${dataDir}".d = {
    user = "freshrss";
    group = "freshrss";
    mode = "0770";
  };

  systemd.tmpfiles.settings."10-freshrss"."${backupDir}".d = {
    user = "freshrss";
    group = "freshrss";
    mode = "0750";
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "edsalkeld@fastmail.com";
  };

  services.phpfpm.pools.freshrss = {
    user = "freshrss";
    group = "freshrss";
    phpEnv.DATA_PATH = dataDir;
    settings = {
      "listen.owner" = "nginx";
      "listen.group" = "nginx";
      "listen.mode" = "0600";
      "pm" = "dynamic";
      "pm.max_children" = 8;
      "pm.max_requests" = 500;
      "pm.start_servers" = 2;
      "pm.min_spare_servers" = 1;
      "pm.max_spare_servers" = 3;
      "catch_workers_output" = true;
    };
  };

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    virtualHosts.${domain} = {
      root = "${pkgs.freshrss}/p";
      enableACME = true;
      forceSSL = true;

      locations."/" = {
        tryFiles = "$uri $uri/ /index.php?$args";
        index = "index.php index.html index.htm";
      };

      # The API uses PHP PATH_INFO, so this must match the FreshRSS module's
      # FastCGI handling rather than a generic PHP location.
      locations."~ ^.+?\\.php(/.*)?$".extraConfig = ''
        fastcgi_pass unix:${config.services.phpfpm.pools.freshrss.socket};
        fastcgi_split_path_info ^(.+\\.php)(/.*)$;
        set $path_info $fastcgi_path_info;
        fastcgi_param PATH_INFO $path_info;
        include ${pkgs.nginx}/conf/fastcgi_params;
        include ${pkgs.nginx}/conf/fastcgi.conf;
      '';
    };
  };

  systemd.services.freshrss-updater = {
    description = "FreshRSS feed updater";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    environment.DATA_PATH = dataDir;
    serviceConfig = {
      Type = "oneshot";
      User = "freshrss";
      Group = "freshrss";
      WorkingDirectory = pkgs.freshrss;
      ExecStart = "${pkgs.freshrss}/app/actualize_script.php";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ dataDir ];
    };
  };

  systemd.timers.freshrss-updater = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/5";
      Persistent = true;
    };
  };

  # FreshRSS's supported automatic export writes a portable SQLite database
  # for every user and prunes old exports itself. Pair it with an archive of
  # the remaining persistent state: config, user metadata, extensions and
  # assets. Cache is rebuildable, and a live copy of db.sqlite is deliberately
  # excluded in favour of the consistent export made immediately beforehand.
  #
  # A restore therefore needs the matching SQLite export and state archive.
  # Both remain on local disk until off-host retention is decided.
  systemd.services.freshrss-sqlite-backup = {
    description = "FreshRSS SQLite backup";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.gzip ];
    environment.DATA_PATH = dataDir;
    script = ''
      config_file=${dataDir}/config.php
      ${pkgs.php}/bin/php -r '
        $path = $argv[1];
        $config = require $path;
        $desired = ["enabled" => true, "retention" => 8];
        if (($config["auto_sqlite_export"] ?? null) !== $desired) {
          $config["auto_sqlite_export"] = $desired;
          $temporary = "$path.tmp";
          file_put_contents($temporary, "<?php\nreturn " . var_export($config, true) . ";\n");
          rename($temporary, $path);
        }
      ' "$config_file"
      ${pkgs.freshrss}/cli/export-sqlite-auto.php
      ${pkgs.findutils}/bin/find ${dataDir}/users -path '*/sqlite-backups/*.sqlite' \
        -type f -exec ${pkgs.coreutils}/bin/chmod 0600 {} +

      timestamp=$(${pkgs.coreutils}/bin/date --utc +%Y%m%dT%H%M%SZ)
      temporary_archive=${backupDir}/.state-$timestamp.tar.gz.tmp
      archive=${backupDir}/state-$timestamp.tar.gz
      ${pkgs.gnutar}/bin/tar --create --gzip --file "$temporary_archive" \
        --exclude='./cache' \
        --exclude='./users/*/db.sqlite*' \
        --exclude='./users/*/sqlite-backups' \
        --directory=${dataDir} .
      ${pkgs.coreutils}/bin/chmod 0600 "$temporary_archive"
      ${pkgs.coreutils}/bin/mv "$temporary_archive" "$archive"
      ${pkgs.findutils}/bin/find ${backupDir} -maxdepth 1 -type f \
        -name 'state-*.tar.gz' -printf '%T@ %p\\n' \
        | ${pkgs.coreutils}/bin/sort -nr \
        | ${pkgs.coreutils}/bin/tail -n +9 \
        | ${pkgs.findutils}/bin/cut -d' ' -f2- \
        | ${pkgs.findutils}/bin/xargs --no-run-if-empty ${pkgs.coreutils}/bin/rm -f
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "freshrss";
      Group = "freshrss";
      WorkingDirectory = pkgs.freshrss;
      UMask = "0077";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ dataDir backupDir ];
    };
  };

  systemd.timers.freshrss-sqlite-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun *-*-* 03:15:00";
      Persistent = true;
    };
  };
}
