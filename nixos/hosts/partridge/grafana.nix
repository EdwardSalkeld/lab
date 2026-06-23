{ config, ... }:

let
  grafanaDomain = "grafana.alcachofa.faith";
  grafanaPort = 3001;
  octopusStaleDataThresholdDays = 4;
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
      notification_settings.receiver = "Email Alcachofa";
      isPaused = false;
    };
  prometheusDatasourceUid = "fdp9rmnopl3wgf";
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
    notification_settings.receiver = "Email Alcachofa";
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

    settings = {
      server = {
        domain = grafanaDomain;
        http_addr = "127.0.0.1";
        http_port = grafanaPort;
        root_url = "https://${grafanaDomain}/";
      };

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
        password = "$__file{${config.sops.secrets."grafana/smtp_password".path}}";
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
      ];
    };

    provision.alerting.rules.settings = {
      apiVersion = 1;
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
      ];
    };

    provision.alerting.contactPoints.settings = {
      apiVersion = 1;
      contactPoints = [
        {
          orgId = 1;
          name = "Email Alcachofa";
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
          ];
        }
      ];
    };

    provision.alerting.policies.settings = {
      apiVersion = 1;
      policies = [
        {
          orgId = 1;
          receiver = "Email Alcachofa";
          group_by = [
            "grafana_folder"
            "alertname"
          ];
        }
      ];
    };
  };

}
