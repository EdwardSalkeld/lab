{ common, builders, ... }:

let
  inherit (common) alertsContactPointName prometheusDatasourceUid;
  inherit (builders) mkLokiThresholdAlert;
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
  # APScheduler logs the outcome even when the journal priority remains info.
  # Three ten-minute poll exceptions without a success in the window warrant
  # attention. A successful poll removes the series immediately on evaluation;
  # NoData stays OK because service/target-down alerts cover a stopped worker.
  mcmTransmissionPollLogs = ''{host="kite", source="journal", systemd_unit="mcm-worker.service"} |= "apscheduler.executors.default:Job" |= "poll_transmission_once ("'';
  mcmTransmissionFailuresAlert = mkLokiThresholdAlert {
    uid = "mcm-transmission-repeated-failures";
    title = "MCM Transmission polling repeatedly fails";
    expr = ''sum(count_over_time(${mcmTransmissionPollLogs} |= "raised an exception" [35m])) unless sum(count_over_time(${mcmTransmissionPollLogs} |= "executed successfully" [35m]))'';
    threshold = 2;
    for = "0s";
    summary = "MCM cannot poll Transmission";
    description = "At least three Transmission polling jobs on kite failed in 35m, with no successful poll in that window. Polls run every ten minutes. Download completion tracking may be stalled. Check mcm-worker.service logs and the remote Transmission RPC server/listener, reachability and configured endpoint. A successful poll clears this alert at the next evaluation.";
    severity = "warning";
    host = "kite";
    service = "mcm";
    dashboardUid = null;
    panelId = null;
  };
in
[
  {
    orgId = 1;
    name = "MCM";
    folder = "Ops";
    interval = "5m";
    rules = [
      mcmSpotifyDisconnectedAlert
      mcmTransmissionFailuresAlert
    ];
  }
]
