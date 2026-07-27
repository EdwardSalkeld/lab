{ pkgs, ... }:

# The chatting handler/worker SQLite DBs accumulate telemetry, audit, dedup and
# outbox rows with no built-in retention, so they grow without bound (the worker
# DB reached ~1.7 GB before the first manual prune). These weekly jobs delete
# rows older than the retention window.
#
# They intentionally do NOT VACUUM: VACUUM needs an exclusive lock and would mean
# stopping the services. DELETE alone bounds growth because SQLite reuses the
# freed pages, so the files settle at a steady-state size instead of climbing.
# Run a manual `VACUUM` after a switch if you ever want to reclaim the pages to
# disk. Each job runs as the DB's owning user so any -wal/-shm files it touches
# keep the ownership the services expect.

let
  retentionDays = 30;

  mkPrune =
    { name, user, database, sql }:
    {
      "chatting-prune-${name}" = {
        description = "Prune old rows from the chatting ${name} SQLite DB";
        # Only run once the DB exists; harmless no-op otherwise.
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
        script = ''
          cutoff=$(date -u -d '${toString retentionDays} days ago' +%Y-%m-%dT%H:%M:%SZ)
          echo "pruning ${database} rows older than $cutoff"
          sqlite3 "${database}" "PRAGMA busy_timeout=60000; ${sql}"
        '';
      };
    };
in
{
  systemd.services =
    (mkPrune {
      name = "worker";
      user = "worker";
      database = "/var/lib/worker/chatting-worker.db";
      sql = ''
        DELETE FROM worker_activity_events WHERE occurred_at < '$cutoff';
        DELETE FROM audit_events WHERE created_at < '$cutoff';
        DELETE FROM run_records WHERE created_at < '$cutoff';
        DELETE FROM egress_outbox WHERE created_at < '$cutoff';
      '';
    })
    // (mkPrune {
      name = "handler";
      user = "handler";
      database = "/var/lib/handler/chatting-message-handler.db";
      sql = ''
        DELETE FROM dispatched_event_ids WHERE dispatched_at < '$cutoff';
        DELETE FROM idempotency_keys WHERE seen_at < '$cutoff';
        DELETE FROM dispatched_events WHERE dispatched_at < '$cutoff';
        DELETE FROM completed_task_ledger WHERE completed_at < '$cutoff';
        DELETE FROM audit_events WHERE created_at < '$cutoff';
        DELETE FROM run_records WHERE created_at < '$cutoff';
      '';
    });

  systemd.timers.chatting-prune-worker = {
    description = "Weekly prune of the chatting worker SQLite DB";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 04:00";
      Persistent = true;
      RandomizedDelaySec = "15m";
    };
  };

  systemd.timers.chatting-prune-handler = {
    description = "Weekly prune of the chatting handler SQLite DB";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 04:10";
      Persistent = true;
      RandomizedDelaySec = "15m";
    };
  };
}
