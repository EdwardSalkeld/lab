{ common, builders, ... }:

let
  inherit (common) alertsContactPointName backupEventsContactPointName lokiDatasourceUid;
  inherit (builders) mkLokiThresholdAlert;
  fourthRsyncLogSelector = ''{host="fourth", source="file", filename="/host/edward/data-sync.log"}'';
  kiteBackblazeLogSelector = ''{host="kite", source="journal", systemd_unit="restic-backups-kite-full.service"}'';
  rsyncErrorPatterns = builtins.concatStringsSep "|" [
    "(?i)rsync error"
    "(?i)io error"
    "(?i)permission denied"
    "(?i)no space left"
    "(?i)connection unexpectedly closed"
    "(?i)failed:"
    "(?i)error code"
    "(?i)code 23"
    "(?i)code 24"
  ];
  rsyncErrorAlert = mkLokiThresholdAlert {
    uid = "fourth-rsync-errors";
    title = "Kite to Fourth rsync errors or failures";
    expr = ''sum(count_over_time(${fourthRsyncLogSelector} |~ "${rsyncErrorPatterns}" [5m]))'';
    threshold = 0;
    for = "2m";
    summary = "Kite to Fourth rsync errors";
    description = "/host/edward/data-sync.log on fourth has matched Kite to Fourth rsync error/failure patterns for 2m. Check the backup log for transfer failures, permissions issues, space exhaustion, or disconnects.";
    severity = "critical";
    panelId = 3;
  };
  rsyncDeleteVolumeAlert = mkLokiThresholdAlert {
    uid = "fourth-rsync-delete-volume";
    title = "Kite to Fourth rsync delete volume";
    expr = ''sum(count_over_time(${fourthRsyncLogSelector} |~ "\\*deleting " [5m]))'';
    threshold = 5;
    for = "2m";
    summary = "Kite to Fourth rsync delete burst";
    description = "/host/edward/data-sync.log on fourth has logged more than 5 Kite to Fourth delete lines in 5m for 2m. This is intentionally sensitive so unexpected churn is visible quickly.";
    severity = "warning";
    panelId = 2;
  };
  backblazeCompletionAlert = mkLokiThresholdAlert {
    uid = "kite-backblaze-completion";
    title = "Kite to Backblaze backup has not completed";
    expr = ''sum(count_over_time(${kiteBackblazeLogSelector} |= "Finished backup at" [8d]))'';
    evaluator = {
      params = [ 1 ];
      type = "lt";
    };
    noDataState = "Alerting";
    for = "5m";
    summary = "Kite to Backblaze backup is overdue";
    description = "restic-backups-kite-full.service on kite has not logged a successful completion in eight days. Check the unit's journal on kite.";
    severity = "critical";
    panelId = 1;
    dashboardUid = "ops-backup-kite-backblaze";
    service = "backup";
    host = "kite";
  };
  backblazeDurationAlert =
    (mkLokiThresholdAlert {
      uid = "kite-backblaze-duration";
      title = "Kite to Backblaze backup duration is high";
      # Preserve completion time as the run identity. A short event window prevents
      # old slow runs from firing for days; separate groups notify for adjacent runs.
      expr = ''max by (bk_time) (max_over_time(${kiteBackblazeLogSelector} |= "Finished backup at" | pattern "Finished backup at <bk_time> after <bk_dur> seconds" | unwrap bk_dur | __error__="" [15m]))'';
      threshold = 600;
      for = "0s";
      summary = "Kite to Backblaze backup exceeded ten minutes";
      description = "The off-site backup completed at {{ $labels.bk_time }} took {{ $values.B.Value }} seconds (threshold: 600 seconds).";
      severity = "warning";
      panelId = 3;
      dashboardUid = "ops-backup-kite-backblaze";
      service = "backup";
      host = "kite";
    })
    // {
      notification_settings = {
        receiver = backupEventsContactPointName;
        group_by = [
          "grafana_folder"
          "alertname"
          "bk_time"
        ];
        group_wait = "0s";
        group_interval = "1m";
        # Longer than the 15m event lifetime, including missing-series eviction.
        repeat_interval = "24h";
      };
    };
  rsyncRecencyAlert = {
    uid = "fourth-rsync-recency";
    title = "Rsync Log Recency";
    condition = "C";
    data = [
      {
        refId = "A";
        datasourceUid = lokiDatasourceUid;
        queryType = "range";
        relativeTimeRange = {
          from = 21600;
          to = 0;
        };
        model = {
          datasource = {
            type = "loki";
            uid = lokiDatasourceUid;
          };
          editorMode = "code";
          expr = "count_over_time(${fourthRsyncLogSelector} | drop detected_level [36h])";
          intervalMs = 1000;
          maxDataPoints = 43200;
          queryType = "range";
          refId = "A";
        };
      }
      {
        refId = "B";
        datasourceUid = "__expr__";
        queryType = "";
        relativeTimeRange = {
          from = 21600;
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
          from = 21600;
          to = 0;
        };
        model = {
          conditions = [
            {
              evaluator = {
                params = [ 3 ];
                type = "lt";
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
    noDataState = "NoData";
    execErrState = "Error";
    for = "5m";
    annotations = {
      __dashboardUid__ = "ops-backups-kite-fourth";
      __panelId__ = "4";
      summary = "Kite to Fourth rsync log recency is low";
      description = "/host/edward/data-sync.log on fourth has fewer than 3 Kite to Fourth log entries across the last 36h for 5m, which suggests the sync may not be running.";
    };
    labels = {
      service = "rsync";
      host = "fourth";
      severity = "warning";
    };
    notification_settings.receiver = alertsContactPointName;
    isPaused = false;
  };
in
[
  {
    orgId = 1;
    name = "Backups";
    folder = "Ops";
    interval = "1m";
    rules = [
      backblazeCompletionAlert
      backblazeDurationAlert
      rsyncRecencyAlert
      rsyncErrorAlert
      rsyncDeleteVolumeAlert
    ];
  }
]
