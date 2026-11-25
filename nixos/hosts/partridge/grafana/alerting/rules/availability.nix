{ common, builders, ... }:

let
  inherit (common) alertsContactPointName prometheusDatasourceUid;
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
in
[
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
]
