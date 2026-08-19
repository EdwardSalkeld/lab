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

  services.promtail = {
    enable = true;
    configuration = {
      server = {
        http_listen_address = "127.0.0.1";
        http_listen_port = 9080;
        grpc_listen_port = 0;
      };

      clients = [
        { url = "http://127.0.0.1:${toString lokiPort}/loki/api/v1/push"; }
      ];

      scrape_configs = [
        {
          job_name = "partridge-systemd-journal";
          journal = {
            max_age = "24h";
            labels = {
              host = "partridge";
              source = "journal";
            };
          };
          relabel_configs = [
            {
              source_labels = [ "__journal__systemd_unit" ];
              regex = "exercise-tracker-hevy-sync.service";
              action = "keep";
            }
            {
              source_labels = [ "__journal__systemd_unit" ];
              target_label = "systemd_unit";
            }
            {
              source_labels = [ "__journal_priority_keyword" ];
              target_label = "level";
            }
          ];
        }
      ];
    };
  };

  systemd.services.promtail = {
    after = [ "loki.service" ];
    wants = [ "loki.service" ];
  };
}
