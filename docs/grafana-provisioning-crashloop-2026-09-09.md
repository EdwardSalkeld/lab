# Grafana provisioning crash loop — 2026-09-09

## Summary

Grafana on `partridge` entered a restart loop after the MCM rename changed a
file-provisioned alert rule. Grafana's failure notifier sent an alert for every
restart until the service was stopped. The service was recovered without data
loss and is now protected against the same trigger on future starts.

## Impact

- Grafana was unavailable while it restarted.
- The failure notifier produced hundreds of repeated Telegram alerts.
- Prometheus, Loki, PostgreSQL, and the configured alert rules were not lost or
  corrupted.

## Detection and timeline

- The alerting service reported repeated Grafana failures; it was then stopped
  manually to stop the notification storm.
- Investigation found 163 restart attempts by 20:38 UTC and a PostgreSQL error
  during alert-rule provisioning.
- A PostgreSQL dump was created at
  `/var/lib/postgresql/grafana-pre-folder-owner-repair-20260909.dump` before
  repair.
- The two affected unified-storage folders were re-owned from the UI user to
  `provisioning:` and Grafana was restarted.
- Grafana subsequently remained active with zero restart attempts and its local
  health endpoint returned `database: ok`.

## Root cause

Grafana 13's unified folder storage has an upstream ORM state-leak defect when
file-based alert provisioning updates rules and a folder retains `user:`
provenance. A later folder-owner lookup then selects `alert_rule` columns from
the `user` table. PostgreSQL rejects the malformed query (`column "guid" does
not exist`), aborts the provisioning transaction, and Grafana exits at startup.

The MCM rule update made this pre-existing data-dependent defect visible. Two
older UI-created folders (`BackupMonitoring` and `Test`) still had
`grafana.app/createdBy` and/or `grafana.app/updatedBy` set to the UI user.

## Why the notification volume was so high

`grafana.service` used systemd's default 100 ms restart delay and had no start
limit. Its `OnFailure` notifier ran after every failed attempt, with no
notification cooldown. The result was a failure alert roughly every three
seconds until the service was manually stopped.

Upstream report: <https://github.com/grafana/grafana/issues/128708>.

## Resolution and prevention

The immediate repair normalized both provenance fields on the affected folder
records to `provisioning:`. This PR adds
`grafana-folder-provenance-repair.service`, a PostgreSQL-backed one-shot unit
that runs before every Grafana start. It only changes folder records whose
`createdBy` or `updatedBy` provenance begins with `user:`. That makes the
workaround durable if a folder is edited in Grafana's UI before an upstream
Grafana release fixes the defect.

The PR also changes Grafana's restart policy to wait 15 seconds between
attempts and stop after three failures within five minutes. The failure
notifier now records a timestamp under `/var/lib` and sends at most one
Telegram message every 15 minutes.

## Follow-up

Remove the guard after upgrading to a Grafana version that includes and has
been verified with an upstream fix for this provisioning defect.
