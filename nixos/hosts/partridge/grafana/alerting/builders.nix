{ lib, common }:

let
  inherit (common)
    alertsContactPointName
    prometheusDatasourceUid
    lokiDatasourceUid
    ;
  octopusStaleDataThresholdDays = 4;
  # Real, persistent filesystems only: ext4 excludes tmpfs/ramfs/fuse/vfat;
  # /nix/store is dropped because it mirrors / on NixOS hosts.
  diskFsSelector = ''{fstype="ext4", mountpoint!~"/nix/store"}'';
in
{
  mkOctopusFreshnessAlert =
    {
      uid,
      title,
      usageType,
      panelId,
    }:
    {
      inherit uid title;
      condition = "C";
      data = [
        {
          refId = "A";
          datasourceUid = "scheduler-postgres";
          queryType = "";
          relativeTimeRange = {
            from = 600;
            to = 0;
          };
          model = {
            datasource = {
              type = "postgres";
              uid = "scheduler-postgres";
            };
            editorMode = "code";
            format = "table";
            intervalMs = 1000;
            maxDataPoints = 43200;
            rawQuery = true;
            rawSql = ''
              SELECT EXTRACT(EPOCH FROM (now() - max(interval_start))) / 86400 AS age_days
              FROM usages
              WHERE usage_type = '${usageType}'
            '';
            refId = "A";
          };
        }
        {
          refId = "B";
          datasourceUid = "__expr__";
          queryType = "";
          relativeTimeRange = {
            from = 0;
            to = 0;
          };
          model = {
            datasource = {
              type = "__expr__";
              uid = "__expr__";
            };
            expression = "A";
            intervalMs = 1000;
            maxDataPoints = 43200;
            reducer = "last";
            refId = "B";
            type = "reduce";
          };
        }
        {
          refId = "C";
          datasourceUid = "__expr__";
          queryType = "";
          relativeTimeRange = {
            from = 0;
            to = 0;
          };
          model = {
            conditions = [
              {
                evaluator = {
                  params = [ octopusStaleDataThresholdDays ];
                  type = "gt";
                };
                operator.type = "and";
                query.params = [ "C" ];
                reducer.type = "last";
                type = "query";
              }
            ];
            datasource = {
              type = "__expr__";
              uid = "__expr__";
            };
            expression = "B";
            intervalMs = 1000;
            maxDataPoints = 43200;
            refId = "C";
            type = "threshold";
          };
        }
      ];
      noDataState = "Alerting";
      execErrState = "Error";
      for = "30m";
      annotations = {
        __dashboardUid__ = "ops-octopus-energy";
        __panelId__ = toString panelId;
        description = "Latest ${usageType} Octopus data is older than ${toString octopusStaleDataThresholdDays} days.";
        summary = "Octopus ${usageType} data is stale";
      };
      labels = {
        service = "octopus";
        usage_type = usageType;
      };
      notification_settings.receiver = alertsContactPointName;
      isPaused = false;
    };
  mkLokiThresholdAlert =
    {
      uid,
      title,
      expr,
      threshold ? 0,
      evaluator ? {
        params = [ threshold ];
        type = "gt";
      },
      for,
      summary,
      description,
      severity,
      panelId,
      dashboardUid ? "ops-backups-kite-fourth",
      service ? "rsync",
      noDataState ? "OK",
      host ? "fourth",
    }:
    {
      inherit uid title;
      condition = "C";
      data = [
        {
          refId = "A";
          datasourceUid = lokiDatasourceUid;
          queryType = "";
          relativeTimeRange = {
            from = 600;
            to = 0;
          };
          model = {
            datasource = {
              type = "loki";
              uid = lokiDatasourceUid;
            };
            editorMode = "code";
            expr = expr;
            instant = true;
            intervalMs = 1000;
            maxDataPoints = 43200;
            queryType = "instant";
            refId = "A";
          };
        }
        {
          refId = "B";
          datasourceUid = "__expr__";
          queryType = "";
          relativeTimeRange = {
            from = 0;
            to = 0;
          };
          model = {
            datasource = {
              type = "__expr__";
              uid = "__expr__";
            };
            expression = "A";
            intervalMs = 1000;
            maxDataPoints = 43200;
            reducer = "last";
            refId = "B";
            type = "reduce";
          };
        }
        {
          refId = "C";
          datasourceUid = "__expr__";
          queryType = "";
          relativeTimeRange = {
            from = 0;
            to = 0;
          };
          model = {
            conditions = [
              {
                inherit evaluator;
                operator.type = "and";
                query.params = [ "C" ];
                reducer.type = "last";
                type = "query";
              }
            ];
            datasource = {
              type = "__expr__";
              uid = "__expr__";
            };
            expression = "B";
            intervalMs = 1000;
            maxDataPoints = 43200;
            refId = "C";
            type = "threshold";
          };
        }
      ];
      inherit noDataState;
      execErrState = "Error";
      inherit for;
      annotations = {
        inherit description summary;
      }
      // lib.optionalAttrs (dashboardUid != null) {
        __dashboardUid__ = dashboardUid;
        __panelId__ = toString panelId;
      };
      labels = {
        service = service;
        inherit host;
        severity = severity;
      };
      notification_settings.receiver = alertsContactPointName;
      isPaused = false;
    };
  # One rule fans out into an alert instance per filesystem (labelled by
  # instance/mountpoint). Warning fires only in the 5–10% band; critical takes
  # over below 5%, so a filling disk escalates rather than double-alerting.
  mkDiskSpaceAlert =
    {
      uid,
      title,
      severity,
      evaluator,
      thresholdText,
    }:
    {
      inherit uid title;
      condition = "C";
      data = [
        {
          refId = "A";
          datasourceUid = prometheusDatasourceUid;
          queryType = "";
          relativeTimeRange = {
            from = 600;
            to = 0;
          };
          model = {
            datasource = {
              type = "prometheus";
              uid = prometheusDatasourceUid;
            };
            editorMode = "code";
            expr = "node_filesystem_avail_bytes${diskFsSelector} / node_filesystem_size_bytes${diskFsSelector}";
            instant = true;
            intervalMs = 1000;
            maxDataPoints = 43200;
            refId = "A";
          };
        }
        {
          refId = "B";
          datasourceUid = "__expr__";
          queryType = "";
          relativeTimeRange = {
            from = 0;
            to = 0;
          };
          model = {
            datasource = {
              type = "__expr__";
              uid = "__expr__";
            };
            expression = "A";
            intervalMs = 1000;
            maxDataPoints = 43200;
            reducer = "last";
            refId = "B";
            type = "reduce";
          };
        }
        {
          refId = "C";
          datasourceUid = "__expr__";
          queryType = "";
          relativeTimeRange = {
            from = 0;
            to = 0;
          };
          model = {
            conditions = [
              {
                evaluator = evaluator;
                operator.type = "and";
                query.params = [ "C" ];
                reducer.type = "last";
                type = "query";
              }
            ];
            datasource = {
              type = "__expr__";
              uid = "__expr__";
            };
            expression = "B";
            intervalMs = 1000;
            maxDataPoints = 43200;
            refId = "C";
            type = "threshold";
          };
        }
      ];
      noDataState = "OK";
      execErrState = "Error";
      for = "15m";
      annotations = {
        summary = "{{ $labels.instance }} {{ $labels.mountpoint }} is low on disk space";
        description = "Free space on {{ $labels.mountpoint }} ({{ $labels.instance }}) has been below ${thresholdText} for 15m.";
      };
      labels = {
        inherit severity;
      };
      notification_settings.receiver = alertsContactPointName;
      isPaused = false;
    };
}
