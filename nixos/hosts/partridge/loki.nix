{ ... }:

let
  lokiDomain = "loki.int.alcachofa.faith";
  lokiPort = 3100;
in
{
  fileSystems."/var/lib/loki" = {
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi5";
    fsType = "ext4";
  };

  alcachofa.partridge.reverseProxy.routes.${lokiDomain}.port = lokiPort;

  services.loki = {
    enable = true;
    dataDir = "/var/lib/loki";

    configuration = {
      auth_enabled = false;

      server = {
        http_listen_address = "127.0.0.1";
        http_listen_port = lokiPort;
        grpc_listen_port = 9096;
      };

      common = {
        instance_addr = "127.0.0.1";
        path_prefix = "/var/lib/loki";
        replication_factor = 1;

        ring.kvstore.store = "inmemory";

        storage.filesystem = {
          chunks_directory = "/var/lib/loki/chunks";
          rules_directory = "/var/lib/loki/rules";
        };
      };

      schema_config.configs = [
        {
          from = "2024-01-01";
          store = "tsdb";
          object_store = "filesystem";
          schema = "v13";
          index = {
            prefix = "index_";
            period = "24h";
          };
        }
      ];

      query_range.results_cache.cache.embedded_cache = {
        enabled = true;
        max_size_mb = 100;
      };

      compactor = {
        working_directory = "/var/lib/loki/compactor";
        retention_enabled = true;
        delete_request_store = "filesystem";
      };

      limits_config.retention_period = "30d";
      analytics.reporting_enabled = false;
    };
  };

  # Promtail was removed in NixOS 26.05. Preserve the same journal stream,
  # labels, and Loki endpoint with its supported successor, Grafana Alloy.
  services.alloy = {
    enable = true;
    extraFlags = [
      "--server.http.listen-addr=127.0.0.1:9080"
      "--server.http.ui-path-prefix=/"
      "--disable-reporting"
    ];
  };

  environment.etc."alloy/partridge-journal.alloy".text = ''
    loki.relabel "partridge_journal" {
      forward_to = []

      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label  = "systemd_unit"
      }

      rule {
        source_labels = ["__journal_priority_keyword"]
        target_label  = "level"
      }
    }

    loki.source.journal "partridge_systemd_journal" {
      forward_to    = [loki.write.local.receiver]
      relabel_rules = loki.relabel.partridge_journal.rules
      matches       = "_SYSTEMD_UNIT=exercise-tracker-hevy-sync.service"
      max_age       = "24h"
      labels = {
        host   = "partridge",
        source = "journal",
      }
    }

    loki.write "local" {
      endpoint {
        url = "http://127.0.0.1:${toString lokiPort}/loki/api/v1/push"
      }
    }
  '';

  systemd.services.alloy = {
    after = [ "loki.service" ];
    wants = [ "loki.service" ];
  };
}
