{ common, ... }:

let
  inherit (common) alertsContactPointName prometheusDatasourceUid;
  mkAlert =
    {
      uid,
      title,
      expr,
      threshold,
      for,
      summary,
      description,
    }:
    {
      inherit uid title for;
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
            inherit expr;
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
      annotations = { inherit summary description; };
      labels = {
        service = "chatting";
        severity = "warning";
      };
      notification_settings.receiver = alertsContactPointName;
      isPaused = false;
    };
in
[
  {
    orgId = 1;
    name = "Chatting quota";
    folder = "Ops";
    interval = "1m";
    rules = [
      (mkAlert {
        uid = "chatting-codex-quota-blocked";
        title = "Chatting Codex quota exhausted";
        expr = "chatting_codex_quota_blocked";
        threshold = 0;
        for = "2m";
        summary = "Codex quota exhausted: Chatting work is queued";
        description = "Codex ordinary usage is blocked. Chatting retains incoming work and resumes when quota is available. Check worker quota metrics and the inbox.";
      })
      (mkAlert {
        uid = "chatting-codex-quota-interrupted";
        title = "Chatting quota interrupted work needs review";
        expr = "chatting_codex_quota_interrupted_tasks";
        threshold = 0;
        for = "2m";
        summary = "Chatting has quota-interrupted work needing review";
        description = "At least one task may have performed actions before quota ran out. Inspect its activity and external state before explicitly resuming it with app.main_quota.";
      })
      (mkAlert {
        uid = "chatting-codex-quota-stale";
        title = "Chatting Codex quota monitoring stale";
        expr = ''(time() - max(chatting_codex_quota_snapshot_timestamp_seconds)) or (301 + 0 * (up{job="chatting-worker"} == 1 unless on() chatting_codex_quota_snapshot_timestamp_seconds))'';
        threshold = 300;
        for = "5m";
        summary = "Chatting cannot read Codex quota";
        description = "The quota reading is missing or over five minutes old. Check chatting-worker logs and Codex authentication; queued work may remain paused until a successful quota read.";
      })
    ];
  }
]
