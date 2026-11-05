{
  config,
  lib,
  pkgs,
  chattingMaintenancePackage,
  ...
}:

let
  cfg = config.services.chatting-prune;
  workerDb = "/var/lib/worker/chatting-worker.db";
  maintenance = "${chattingMaintenancePackage}/bin/chatting-db-maintenance";
  mkPrune =
    {
      name,
      user,
      database,
      script,
    }:
    {
      "chatting-prune-${name}" = {
        description = "Prune old rows from the chatting ${name} SQLite DB";
        unitConfig.ConditionPathExists = database;
        path = [
          pkgs.coreutils
          pkgs.sqlite
        ];
        serviceConfig = {
          Type = "oneshot";
          User = user;
          Group = user;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          ReadWritePaths = [ (builtins.dirOf database) ];
        };
        inherit script;
      };
    };
in
{
  options.services.chatting-prune = {
    retentionDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 14;
      description = "Days of completed-run diagnostics to retain in Chatting SQLite databases.";
    };
    deliveryRetentionDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = "Independent retention window for delivery and deduplication records.";
    };
  };

  config = {
    environment.systemPackages = [ chattingMaintenancePackage ];
    systemd.services =
      (mkPrune {
        name = "worker";
        user = "worker";
        database = workerDb;
        script = ''
          # Idempotent historical cleanup also catches late copies from old
          # supervisors that were still draining during deployment.
          ${maintenance} strip-audit-transcripts --db ${workerDb}
          ${maintenance} prune-worker --db ${workerDb} --retention-days ${toString cfg.retentionDays}

          # Delivery history is independent of run diagnostics. Never discard
          # pending sends or sends associated with unfinished inbox work.
          cutoff=$(date -u -d '${toString cfg.deliveryRetentionDays} days ago' +%Y-%m-%dT%H:%M:%SZ)
          sqlite3 ${workerDb} "PRAGMA busy_timeout=60000;
            DELETE FROM egress_outbox
            WHERE publish_state = 'acked' AND julianday(updated_at) < julianday('$cutoff')
              AND NOT EXISTS (SELECT 1 FROM worker_inbox AS inbox
                WHERE inbox.task_id = egress_outbox.task_id AND inbox.state != 'completed');"
        '';
      })
      // (mkPrune {
        name = "handler";
        user = "handler";
        database = "/var/lib/handler/chatting-message-handler.db";
        script = ''
          cutoff=$(date -u -d '${toString cfg.retentionDays} days ago' +%Y-%m-%dT%H:%M:%SZ)
          delivery_cutoff=$(date -u -d '${toString cfg.deliveryRetentionDays} days ago' +%Y-%m-%dT%H:%M:%SZ)
          sqlite3 /var/lib/handler/chatting-message-handler.db "PRAGMA busy_timeout=60000;
            DELETE FROM audit_events WHERE julianday(created_at) < julianday('$cutoff');
            DELETE FROM run_records WHERE julianday(created_at) < julianday('$cutoff');
            DELETE FROM dispatched_event_ids WHERE julianday(dispatched_at) < julianday('$delivery_cutoff');
            DELETE FROM idempotency_keys WHERE julianday(seen_at) < julianday('$delivery_cutoff');
            DELETE FROM dispatched_events WHERE julianday(dispatched_at) < julianday('$delivery_cutoff');
            DELETE FROM completed_task_ledger WHERE julianday(completed_at) < julianday('$delivery_cutoff');"
        '';
      });

    systemd.timers.chatting-prune-worker = {
      description = "Daily prune of the chatting worker SQLite DB";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 04:00:00";
        Persistent = true;
        RandomizedDelaySec = "15m";
      };
    };

    systemd.timers.chatting-prune-handler = {
      description = "Daily prune of the chatting handler SQLite DB";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 04:10:00";
        Persistent = true;
        RandomizedDelaySec = "15m";
      };
    };
  };
}
