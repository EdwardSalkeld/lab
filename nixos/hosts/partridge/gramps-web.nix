{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Gramps Web 26.10.0, pinned so a reboot cannot silently upgrade the backend.
  image = "ghcr.io/gramps-project/grampsweb:26.10.0@sha256:27017b77784ebc8fe9b4b84e3baab8fa529f1f715f4691bc5d1979b874c216ec";
  stateDir = "/var/lib/gramps-web";
  treeId = "48c9f716-8034-4ce8-9343-ceaa4b940866";
  envFile = config.sops.templates."gramps-web.env".path;
  volumes = [
    "${stateDir}/db:/root/.gramps/grampsdb"
    "${stateDir}/media:/app/media"
    "${stateDir}/thumbnail-cache:/app/thumbnail_cache"
    "${stateDir}/cache:/app/cache"
    "${stateDir}/tmp:/tmp"
  ];
  environment = {
    GRAMPSWEB_TREE = "Salkeld family";
    GRAMPSWEB_TREE_ID = treeId;
    GRAMPSWEB_POSTGRES_HOST = "127.0.0.1";
    GRAMPSWEB_POSTGRES_PORT = "5432";
    GRAMPSWEB_POSTGRES_USER = "gramps";
    GRAMPSWEB_NEW_DB_BACKEND = "sharedpostgresql";
    GRAMPSWEB_BASE_URL = "http://10.4.1.30:5050/";
    GRAMPSWEB_CELERY_CONFIG__broker_url = "redis://127.0.0.1:6381/0";
    GRAMPSWEB_CELERY_CONFIG__result_backend = "redis://127.0.0.1:6381/0";
    GRAMPSWEB_RATELIMIT_STORAGE_URI = "redis://127.0.0.1:6381/1";
    GRAMPSWEB_DISABLE_TELEMETRY = "true";
    GRAMPSWEB_REGISTRATION_DISABLED = "true";
  };
  bootstrap = ./gramps-web-bootstrap.py;
in
{
  sops.secrets = lib.genAttrs [ "gramps-web/db-password" "gramps-web/secret-key" ] (name: {
    sopsFile = ./secrets/gramps-web.yaml;
    key = if name == "gramps-web/db-password" then "db_password" else "secret_key";
    restartUnits = [
      "gramps-web-db-setup.service"
      "podman-gramps-web.service"
      "podman-gramps-web-worker.service"
    ];
  });
  sops.templates."gramps-web.env" = {
    mode = "0400";
    content = ''
      GRAMPSWEB_SECRET_KEY=${config.sops.placeholder."gramps-web/secret-key"}
      GRAMPSWEB_POSTGRES_PASSWORD=${config.sops.placeholder."gramps-web/db-password"}
      GRAMPSWEB_USER_DB_URI=postgresql://gramps:${
        config.sops.placeholder."gramps-web/db-password"
      }@127.0.0.1:5432/grampswebuser
      GRAMPSWEB_SEARCH_INDEX_DB_URI=postgresql://gramps:${
        config.sops.placeholder."gramps-web/db-password"
      }@127.0.0.1:5432/gramps
    '';
  };

  # Reuse Partridge's PostgreSQL and its existing nightly all-database dump.
  services.postgresql.ensureDatabases = [
    "gramps"
    "grampswebuser"
  ];
  services.postgresql.ensureUsers = [
    {
      name = "gramps";
      ensureDBOwnership = true;
    }
  ];
  services.postgresql.authentication = lib.mkAfter ''
    host gramps,grampswebuser gramps 127.0.0.1/32 scram-sha-256
  '';
  systemd.services.gramps-web-db-setup = {
    description = "Configure Gramps Web PostgreSQL credentials and ownership";
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
      Group = "postgres";
      LoadCredential = "db-password:${config.sops.secrets."gramps-web/db-password".path}";
    };
    script = ''
            db_password="$(cat "$CREDENTIALS_DIRECTORY/db-password")"
            ${config.services.postgresql.package}/bin/psql -v ON_ERROR_STOP=1 --set=db_password="$db_password" --dbname=postgres <<'SQL'
            ALTER ROLE gramps WITH LOGIN PASSWORD :'db_password';
            ALTER DATABASE grampswebuser OWNER TO gramps;
      SQL
    '';
  };

  services.redis.servers.gramps-web = {
    enable = true;
    bind = "127.0.0.1";
    port = 6381;
  };
  systemd.tmpfiles.rules = map (dir: "d ${stateDir}/${dir} 0700 root root -") [
    "db"
    "media"
    "thumbnail-cache"
    "cache"
    "tmp"
  ];

  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      gramps-web = {
        inherit image environment volumes;
        environmentFiles = [ envFile ];
        # Host networking allows loopback-only access to PostgreSQL and Redis.
        # Explicit gunicorn binding keeps the API behind the LAN-only proxy.
        podman.sdnotify = "healthy";
        extraOptions = [
          "--network=host"
          "--health-cmd=python3 -c \"import urllib.request; urllib.request.urlopen('http://127.0.0.1:5051/', timeout=5)\""
          "--health-interval=10s"
          "--health-start-period=60s"
          "--health-retries=6"
        ];
        cmd = [
          "gunicorn"
          "-w"
          "1"
          "-b"
          "127.0.0.1:5051"
          "gramps_webapi.wsgi:app"
          "--timeout"
          "120"
          "--limit-request-line"
          "8190"
        ];
      };
      gramps-web-worker = {
        inherit image environment volumes;
        environmentFiles = [ envFile ];
        extraOptions = [ "--network=host" ];
        dependsOn = [ "gramps-web" ];
        cmd = [
          "celery"
          "-A"
          "gramps_webapi.celery"
          "worker"
          "--loglevel=INFO"
          "--concurrency=1"
          "--max-tasks-per-child=50"
        ];
      };
    };
  };
  systemd.services.podman-gramps-web = {
    after = [
      "gramps-web-db-setup.service"
      "redis-gramps-web.service"
    ];
    requires = [
      "gramps-web-db-setup.service"
      "redis-gramps-web.service"
    ];
    # Run once per app start, with the same image, credentials and tree volume.
    preStart = lib.mkAfter ''
      ${pkgs.podman}/bin/podman run --rm --network=host \
        --env-file ${envFile} \
        --env GRAMPSWEB_POSTGRES_HOST=127.0.0.1 \
        --env GRAMPSWEB_POSTGRES_USER=gramps \
        --env GRAMPSWEB_POSTGRES_PORT=5432 \
        --env GRAMPSWEB_TREE='Salkeld family' \
        --env GRAMPSWEB_TREE_ID=${treeId} \
        --env GRAMPSWEB_NEW_DB_BACKEND=sharedpostgresql \
        --env GRAMPSWEB_DISABLE_TELEMETRY=true \
        --volume ${stateDir}/db:/root/.gramps/grampsdb \
        --volume ${stateDir}/cache:/app/cache \
        --volume ${bootstrap}:/bootstrap.py:ro \
        --entrypoint python3 ${image} /bootstrap.py
    '';
    serviceConfig.TimeoutStartSec = lib.mkForce "15min";
  };
  systemd.services.podman-gramps-web-worker = {
    after = [
      "gramps-web-db-setup.service"
      "redis-gramps-web.service"
    ];
    requires = [
      "gramps-web-db-setup.service"
      "redis-gramps-web.service"
    ];
    serviceConfig.TimeoutStartSec = lib.mkForce "15min";
  };

  # Direct LAN endpoint for stage 2. Nothing routes here from Cloudflare yet.
  networking.firewall.interfaces.ens18.allowedTCPPorts = [ 5050 ];
  services.nginx.virtualHosts."gramps-web-lan" = {
    listen = [
      {
        addr = "10.4.1.30";
        port = 5050;
      }
    ];
    locations."/" = {
      proxyPass = "http://127.0.0.1:5051";
      extraConfig = ''
        allow 10.4.1.0/24;
        deny all;
        client_max_body_size 250m;
        proxy_read_timeout 300s;
      '';
    };
  };

  # PostgreSQL dumps cover genealogy, accounts and search. Metadata and media
  # need their own files in the existing encrypted off-host Restic repository.
  services.restic.backups.partridge-postgres.paths = [
    "${stateDir}/db"
    "${stateDir}/media"
  ];
}
