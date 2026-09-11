{ config, pkgs, grafanaPackage, ... }:

let
  grafanaDomain = "grafana.alcachofa.faith";
  grafanaPort = 3001;
  octopusStaleDataThresholdDays = 4;
  alertsContactPointName = "Alcachofa Alerts";
  alertsTelegramChatId = "-5594899826";
  grafanaFailureNotify = pkgs.writeShellScript "grafana-failure-notify" ''
    set -euo pipefail

    unit="''${1:?usage: grafana-failure-notify <systemd-unit>}"
    state_dir=/var/lib/grafana-failure-notify
    cooldown_seconds=900
    exec 9>"$state_dir/lock"
    ${pkgs.util-linux}/bin/flock 9

    now_epoch="$(${pkgs.coreutils}/bin/date +%s)"
    last_notified=0
    if [ -r "$state_dir/last-notified" ]; then
      read -r last_notified < "$state_dir/last-notified" || true
    fi
    if ! [[ "$last_notified" =~ ^[0-9]+$ ]]; then
      last_notified=0
    fi
    if (( now_epoch - last_notified < cooldown_seconds )); then
      exit 0
    fi

    host="$("/run/current-system/sw/bin/hostname" -s)"
    now="$("/run/current-system/sw/bin/date" -u +"%Y-%m-%d %H:%M:%S UTC")"
    result="$("/run/current-system/sw/bin/systemctl" show "$unit" --property=Result --value 2>/dev/null || true)"
    active_state="$("/run/current-system/sw/bin/systemctl" show "$unit" --property=ActiveState --value 2>/dev/null || true)"
    sub_state="$("/run/current-system/sw/bin/systemctl" show "$unit" --property=SubState --value 2>/dev/null || true)"
    text="Grafana failed on $host at $now. unit=$unit active=$active_state sub=$sub_state result=''${result:-unknown}. Check journalctl -u $unit -n 80 --no-pager."

    ${pkgs.curl}/bin/curl \
      --fail \
      --silent \
      --show-error \
      --data-urlencode "chat_id=${alertsTelegramChatId}" \
      --data-urlencode "text=$text" \
      --data-urlencode "disable_web_page_preview=true" \
      "https://api.telegram.org/bot''${GRAFANA_TELEGRAM_BOT_TOKEN}/sendMessage"

    printf '%s\n' "$now_epoch" > "$state_dir/last-notified"
  '';
  # Grafana 13 can crash-loop during file-based alert provisioning when a
  # unified-storage folder retains UI user provenance. Normalize it before
  # startup until https://github.com/grafana/grafana/issues/128708 is fixed.
  grafanaFolderProvenanceRepair = pkgs.writeShellScript "grafana-folder-provenance-repair" ''
    set -euo pipefail

    exec ${config.services.postgresql.package}/bin/psql \
      --dbname=grafana \
      --set=ON_ERROR_STOP=1 \
      --quiet \
      --command="
        UPDATE resource
        SET value = jsonb_set(
          jsonb_set(
            value::jsonb,
            '{metadata,annotations,grafana.app/createdBy}',
            to_jsonb('provisioning:'::text)
          ),
          '{metadata,annotations,grafana.app/updatedBy}',
          to_jsonb('provisioning:'::text)
        )::text
        WHERE \"group\" = 'folder.grafana.app'
          AND (
            value::jsonb #>> '{metadata,annotations,grafana.app/createdBy}' LIKE 'user:%'
            OR value::jsonb #>> '{metadata,annotations,grafana.app/updatedBy}' LIKE 'user:%'
          );
      "
  '';
  # Grafana's default Telegram message dumps the firing value, every label and
  # the raw annotation list. Our rules already carry a tidy summary/description,
  # so render just those two lines plus the Source/Silence links. Email keeps
  # Grafana's own HTML template; only the Telegram receiver uses this.
  alertsTelegramTemplate = ''
    {{ define "alcachofa.alert" }}{{ if .Annotations.summary }}{{ .Annotations.summary }}{{ else if .Labels.alertname }}{{ .Labels.alertname }}{{ if .Labels.instance }} on {{ .Labels.instance }}{{ end }}{{ else if .Labels.instance }}Alert on {{ .Labels.instance }}{{ else }}Alert{{ end }}
    {{ if .Annotations.description }}
    {{ .Annotations.description }}
    {{ end }}{{ if gt (len .GeneratorURL) 0 }}Source: {{ .GeneratorURL }}
    {{ end }}{{ if gt (len .SilenceURL) 0 }}Silence: {{ .SilenceURL }}
    {{ end }}{{ end }}
    {{ define "alcachofa.message" }}{{ range .Alerts.Firing }}{{ template "alcachofa.alert" . }}
    {{ end }}{{ range .Alerts.Resolved }}✅ Resolved - {{ template "alcachofa.alert" . }}
    {{ end }}{{ end }}
  '';
  mkOctopusFreshnessAlert =
    { uid, title, usageType, panelId }:
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
  prometheusDatasourceUid = "fdp9rmnopl3wgf";
  lokiDatasourceUid = "ce6j6e2q9rapsa";
  fourthRsyncLogSelector = ''{host="fourth", source="file", filename="/host/edward/data-sync.log"}'';
  # Single rule over up; Grafana fans it out into one alert instance per scrape
  # target, labelled by `instance`/`job`. up == 0 means the scrape failed (host,
  # exporter or service down) while the series still exists; NoData covers the
  # case where Prometheus itself stops returning the series.
  targetDownAlert = {
    uid = "prometheus-target-down";
    title = "Scrape target down";
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
          expr = "up";
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
              evaluator = {
                params = [ 1 ];
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
    noDataState = "Alerting";
    execErrState = "Error";
    for = "5m";
    annotations = {
      summary = "{{ $labels.instance }} ({{ $labels.job }}) is down";
      description = "Prometheus scrape target {{ $labels.instance }} (job {{ $labels.job }}) has been down for 5m (up == 0). The host, exporter or service is likely unreachable.";
    };
    labels = {
      severity = "critical";
    };
    notification_settings.receiver = alertsContactPointName;
    isPaused = false;
  };
  websiteDownAlert = {
    uid = "public-website-down";
    title = "Public website down";
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
          expr = ''probe_success{job="http-probe"}'';
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
              evaluator = {
                params = [ 1 ];
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
    noDataState = "Alerting";
    execErrState = "Error";
    for = "5m";
    annotations = {
      summary = "{{ $labels.instance }} is down";
      description = "The public HTTP(S) probe for {{ $labels.instance }} has failed for 5m. This checks DNS, TLS and a successful HTTP response from Partridge.";
    };
    labels = {
      severity = "critical";
      service = "website";
    };
    notification_settings.receiver = alertsContactPointName;
    isPaused = false;
  };
  systemdUnitFailedAlert = {
    uid = "systemd-unit-failed";
    title = "Systemd unit failed";
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
          expr = ''node_systemd_unit_state{state="failed"}'';
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
              evaluator = {
                params = [ 0 ];
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
    for = "5m";
    annotations = {
      summary = "{{ $labels.name }} is failed on {{ $labels.instance }}";
      description = "Systemd unit {{ $labels.name }} on {{ $labels.instance }} has been in failed state for 5m. Check journalctl -u {{ $labels.name }} on the affected host.";
    };
    labels = {
      service = "systemd";
      severity = "critical";
    };
    notification_settings.receiver = alertsContactPointName;
    isPaused = false;
  };
  # A unit can be cleanly stopped without entering the failed state, so keep
  # the two media services covered explicitly as well as by the generic
  # failed-unit rule above.
  kiteMediaServicesAlert = {
    uid = "kite-media-services-inactive";
    title = "Kite media service inactive";
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
          expr = ''node_systemd_unit_state{instance="kite.int.alcachofa.faith:9100",name=~"jellyfin.service|navidrome.service",state="active"}'';
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
              evaluator = {
                params = [ 1 ];
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
    noDataState = "Alerting";
    execErrState = "Error";
    for = "5m";
    annotations = {
      summary = "{{ $labels.name }} is inactive on Kite";
      description = "Kite media service {{ $labels.name }} has not been active for 5m. Check systemctl status {{ $labels.name }} on kite.";
    };
    labels = {
      service = "kite-media";
      severity = "critical";
    };
    notification_settings.receiver = alertsContactPointName;
    isPaused = false;
  };
  # MCM pauses ingest/reconcile/plays when its Spotify refresh token is missing or
  # expired (§8c re-auth). The app always exports mcm_spotify_connected (1 connected,
  # 0 reconnect-needed), so alert when it reads 0. NoData is left OK: a full MCM outage
  # drops the series and is already covered by the target-down alert.
  mcmSpotifyDisconnectedAlert = {
    uid = "mcm-spotify-disconnected";
    title = "MCM Spotify disconnected";
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
          expr = "mcm_spotify_connected";
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
              evaluator = {
                params = [ 1 ];
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
    noDataState = "OK";
    execErrState = "Error";
    for = "10m";
    annotations = {
      summary = "MCM is disconnected from Spotify";
      description = "mcm_spotify_connected is 0 — the Spotify refresh token is missing or expired, so ingest/reconcile/plays are paused until you reconnect at https://mcm.alcachofa.faith/.";
    };
    labels = {
      service = "mcm";
      severity = "warning";
    };
    notification_settings.receiver = alertsContactPointName;
    isPaused = false;
  };
  # Real, persistent filesystems only: ext4 excludes tmpfs/ramfs/fuse/vfat;
  # /nix/store is dropped because it mirrors / on NixOS hosts.
  diskFsSelector = ''{fstype="ext4", mountpoint!~"/nix/store"}'';
  mkLokiLogCountAlert =
    {
      uid,
      title,
      expr,
      threshold,
      for,
      summary,
      description,
      severity,
      panelId,
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
                evaluator = {
                  params = [ threshold ];
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
      noDataState = "OK";
      execErrState = "Error";
      inherit for;
      annotations = {
        __dashboardUid__ = "ops-backups-kite-fourth";
        __panelId__ = toString panelId;
        inherit description summary;
      };
      labels = {
        service = "rsync";
        host = "fourth";
        severity = severity;
      };
      notification_settings.receiver = alertsContactPointName;
      isPaused = false;
    };
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
  rsyncErrorAlert = mkLokiLogCountAlert {
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
  rsyncDeleteVolumeAlert = mkLokiLogCountAlert {
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
          expr = ''count_over_time(${fourthRsyncLogSelector} | drop detected_level [36h])'';
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
  # One rule fans out into an alert instance per filesystem (labelled by
  # instance/mountpoint). Warning fires only in the 5–10% band; critical takes
  # over below 5%, so a filling disk escalates rather than double-alerting.
  mkDiskSpaceAlert =
    { uid, title, severity, evaluator, thresholdText }:
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
            expr = ''node_filesystem_avail_bytes${diskFsSelector} / node_filesystem_size_bytes${diskFsSelector}'';
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
in
{
  alcachofa.partridge.reverseProxy.routes.${grafanaDomain}.port = grafanaPort;

  sops.secrets."grafana/smtp_password" = {
    sopsFile = ./secrets/grafana-smtp.yaml;
    key = "smtp_password";
    owner = "grafana";
    group = "grafana";
    mode = "0400";
  };
  sops.secrets."grafana/telegram_bot_token" = {
    sopsFile = ./secrets/grafana-telegram.yaml;
    key = "telegram_bot_token";
    owner = "grafana";
    group = "grafana";
    mode = "0400";
  };
  sops.secrets."grafana/secret_key" = {
    sopsFile = ./secrets/grafana-security.yaml;
    key = "secret_key";
    owner = "grafana";
    group = "grafana";
    mode = "0400";
  };
  sops.templates."grafana-alerting.env" = {
    owner = "grafana";
    group = "grafana";
    mode = "0400";
    content = ''
      GRAFANA_SMTP_PASSWORD=${config.sops.placeholder."grafana/smtp_password"}
      GRAFANA_TELEGRAM_BOT_TOKEN=${config.sops.placeholder."grafana/telegram_bot_token"}
    '';
  };

  systemd.services.grafana.serviceConfig.EnvironmentFile =
    config.sops.templates."grafana-alerting.env".path;
  systemd.services.grafana-folder-provenance-repair = {
    description = "Normalize Grafana unified-folder provenance before startup";
    before = [ "grafana.service" ];
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      Group = "postgres";
      ExecStart = grafanaFolderProvenanceRepair;
    };
  };
  systemd.services.grafana.requires = [ "grafana-folder-provenance-repair.service" ];
  systemd.services.grafana.after = [ "grafana-folder-provenance-repair.service" ];
  systemd.services.grafana.unitConfig = {
    StartLimitIntervalSec = "5min";
    StartLimitBurst = 3;
  };
  systemd.services.grafana.serviceConfig.RestartSec = "15s";
  systemd.services.grafana.onFailure = [ "grafana-failure-notify.service" ];
  systemd.services.grafana-failure-notify = {
    description = "Notify Telegram when Grafana fails (15 minute cooldown)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "grafana-failure-notify";
      StateDirectoryMode = "0700";
      EnvironmentFile = config.sops.templates."grafana-alerting.env".path;
      ExecStart = "${grafanaFailureNotify} grafana.service";
    };
  };

  services.postgresql = {
    ensureDatabases = [ "grafana" ];
    ensureUsers = [
      {
        name = "grafana";
        ensureDBOwnership = true;
      }
    ];
  };

  services.grafana = {
    enable = true;
    package = grafanaPackage;

    settings = {
      server = {
        domain = grafanaDomain;
        http_addr = "127.0.0.1";
        http_port = grafanaPort;
        root_url = "https://${grafanaDomain}/";
      };

      security.secret_key = "$__file{${config.sops.secrets."grafana/secret_key".path}}";

      database = {
        type = "postgres";
        host = "/run/postgresql";
        name = "grafana";
        user = "grafana";
      };

      users = {
        allow_sign_up = false;
        allow_org_create = false;
      };

      smtp = {
        enabled = true;
        host = "smtp.fastmail.com:587";
        user = "edsalkeld@fastmail.com";
        password = "$__env{GRAFANA_SMTP_PASSWORD}";
        from_address = "edsalkeld@fastmail.com";
        from_name = "Grafana";
        startTLS_policy = "MandatoryStartTLS";
      };
    };

    provision.datasources.settings = {
      apiVersion = 1;
      datasources = [
        {
          name = "prometheus";
          uid = "fdp9rmnopl3wgf";
          type = "prometheus";
          access = "proxy";
          url = "http://127.0.0.1:9090";
          isDefault = true;
          editable = true;
        }
        {
          name = "loki";
          uid = "ce6j6e2q9rapsa";
          type = "loki";
          access = "proxy";
          url = "http://127.0.0.1:3100";
          editable = true;
        }
        {
          name = "scheduler-postgres";
          uid = "scheduler-postgres";
          type = "postgres";
          access = "proxy";
          url = "/run/postgresql";
          user = "grafana";
          jsonData = {
            database = "scheduler";
            sslmode = "disable";
          };
          editable = true;
        }
        {
          name = "exercise-tracker-postgres";
          uid = "exercise-tracker-postgres";
          type = "postgres";
          access = "proxy";
          url = "/run/postgresql";
          user = "grafana";
          jsonData = {
            database = "exercise_tracker";
            sslmode = "disable";
          };
          editable = true;
        }
      ];
    };

    provision.dashboards.settings = {
      apiVersion = 1;
      providers = [
        {
          name = "ops";
          folder = "Ops";
          allowUiUpdates = false;
          options.path = ./grafana/dashboards/ops;
        }
        {
          name = "fitness";
          folder = "Fitness";
          allowUiUpdates = false;
          options.path = ./grafana/dashboards/fitness;
        }
        {
          name = "music";
          folder = "Music";
          allowUiUpdates = false;
          options.path = ./grafana/dashboards/music;
        }
        {
          name = "chatting";
          folder = "Chatting";
          allowUiUpdates = false;
          options.path = ./grafana/dashboards/chatting;
        }
      ];
    };

    provision.alerting.rules.settings = {
      apiVersion = 1;
      deleteRules = [
        {
          orgId = 1;
          uid = "cf5pa2mc5o0zkc";
        }
        {
          orgId = 1;
          uid = "af5pb11hibn5sd";
        }
        {
          orgId = 1;
          uid = "aenyejmx1k2rka";
        }
        {
          orgId = 1;
          uid = "df14h5t71ue4gc";
        }
      ];
      groups = [
        {
          orgId = 1;
          name = "Octopus Data Freshness";
          folder = "Ops";
          interval = "1h";
          rules = [
            (mkOctopusFreshnessAlert {
              uid = "octopus-electricity-data-stale";
              title = "Octopus electricity data stale";
              usageType = "electricity";
              panelId = 1;
            })
            (mkOctopusFreshnessAlert {
              uid = "octopus-gas-data-stale";
              title = "Octopus gas data stale";
              usageType = "gas";
              panelId = 2;
            })
          ];
        }
        {
          orgId = 1;
          name = "Target Availability";
          folder = "Ops";
          interval = "1m";
          rules = [
            targetDownAlert
          ];
        }
        {
          orgId = 1;
          name = "Public Website Availability";
          folder = "Ops";
          interval = "1m";
          rules = [
            websiteDownAlert
          ];
        }
        {
          orgId = 1;
          name = "Systemd Units";
          folder = "Ops";
          interval = "1m";
          rules = [
            systemdUnitFailedAlert
          ];
        }
        {
          orgId = 1;
          name = "Kite Media Services";
          folder = "Ops";
          interval = "1m";
          rules = [
            kiteMediaServicesAlert
          ];
        }
        {
          orgId = 1;
          name = "Disk Space";
          folder = "Ops";
          interval = "5m";
          rules = [
            (mkDiskSpaceAlert {
              uid = "disk-space-low-warning";
              title = "Disk space low";
              severity = "warning";
              thresholdText = "10%";
              evaluator = {
                params = [
                  0.05
                  0.10
                ];
                type = "within_range";
              };
            })
            (mkDiskSpaceAlert {
              uid = "disk-space-low-critical";
              title = "Disk space critically low";
              severity = "critical";
              thresholdText = "5%";
              evaluator = {
                params = [ 0.05 ];
                type = "lt";
              };
            })
          ];
        }
        {
          orgId = 1;
          name = "MCM";
          folder = "Ops";
          interval = "5m";
          rules = [
            mcmSpotifyDisconnectedAlert
          ];
        }
        {
          orgId = 1;
          name = "Backups";
          folder = "Ops";
          interval = "1m";
          rules = [
            rsyncRecencyAlert
            rsyncErrorAlert
            rsyncDeleteVolumeAlert
          ];
        }
      ];
    };

    provision.alerting.contactPoints.settings = {
      apiVersion = 1;
      contactPoints = [
        {
          orgId = 1;
          name = alertsContactPointName;
          receivers = [
            {
              uid = "benye0c2pvif4a";
              name = "Email Alcachofa";
              type = "email";
              disableResolveMessage = false;
              settings = {
                addresses = "edsalkeld@fastmail.com";
                singleEmail = false;
              };
            }
            {
              uid = "telegram-alerts";
              name = "Telegram Alerts";
              type = "telegram";
              disableResolveMessage = false;
              settings = {
                bottoken = "$GRAFANA_TELEGRAM_BOT_TOKEN";
                chatid = alertsTelegramChatId;
                uploadImage = false;
                message = ''{{ template "alcachofa.message" . }}'';
                parse_mode = "None";
                disable_web_page_preview = true;
              };
            }
          ];
        }
      ];
    };

    provision.alerting.templates.settings = {
      apiVersion = 1;
      templates = [
        {
          orgId = 1;
          name = "alcachofa-telegram";
          template = alertsTelegramTemplate;
        }
      ];
    };

    provision.alerting.policies.settings = {
      apiVersion = 1;
      policies = [
        {
          orgId = 1;
          receiver = alertsContactPointName;
          group_by = [
            "grafana_folder"
            "alertname"
          ];
        }
      ];
    };
  };

}
