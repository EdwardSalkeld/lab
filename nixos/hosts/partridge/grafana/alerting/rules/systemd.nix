{ common, builders, ... }:

let
  inherit (common) alertsContactPointName prometheusDatasourceUid;
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
  # Units with a RestartSec never hit systemd's start limit, so a crash loop
  # never reaches the failed state above. More than 3 automatic restarts in
  # 30m leaves room for bitwarden-mirror's 15m on-failure retry (at most 2).
  # No data means no host exports the counter, which is not a loop.
  systemdUnitRestartLoopAlert = {
    uid = "systemd-unit-restart-loop";
    title = "Systemd unit restart loop";
    condition = "C";
    data = [
      {
        refId = "A";
        datasourceUid = prometheusDatasourceUid;
        queryType = "";
        relativeTimeRange = {
          from = 1800;
          to = 0;
        };
        model = {
          datasource = {
            type = "prometheus";
            uid = prometheusDatasourceUid;
          };
          editorMode = "code";
          expr = "increase(node_systemd_service_restart_total[30m])";
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
                params = [ 3 ];
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
    for = "5m";
    annotations = {
      summary = "{{ $labels.name }} is restart-looping on {{ $labels.instance }}";
      description = "Systemd restarted {{ $labels.name }} on {{ $labels.instance }} {{ printf \"%.0f\" $values.B.Value }} times in the last 30m. With a RestartSec it never hits the start limit, so it never shows as failed. Check systemctl status {{ $labels.name }} and journalctl -u {{ $labels.name }} -b on the affected host.";
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
in
[
  {
    orgId = 1;
    name = "Systemd Units";
    folder = "Ops";
    interval = "1m";
    rules = [
      systemdUnitFailedAlert
      systemdUnitRestartLoopAlert
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
]
