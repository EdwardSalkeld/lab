# Partridge PostgreSQL 17 to 18

Partridge runs a single PostgreSQL 17 cluster on `/var/lib/postgresql` with
Grafana, Forgejo, exercise tracker, scheduler, network inventory, Octopus and
the wantlist database among its clients. The data directory is
`/var/lib/postgresql/17`; NixOS derives `/var/lib/postgresql/18` for version 18.
Changing the NixOS package alone does not migrate the database.

## Preparation and rehearsal

- A fresh `pg_dumpall` backup was restored from the restic repository in an
  isolated container on 2026-11-21. This establishes logical recovery, not
  point-in-time recovery or an atomic snapshot across all databases.
- A clean physical copy of the 17.12 cluster was upgraded with `pg_upgrade
  --check` and copy mode to Nix PostgreSQL 18.6 in a network-isolated Luna
  container, using the live locale archive. Database and role names and 256
  table row counts matched. Collation versions matched and staged analysis
  completed. This did not exercise the NixOS service switch or applications.
- The current flake pins PostgreSQL 18.7. Build the target system and realise
  its closure before downtime; check that it selects the expected 18 package
  and directory. Confirm available space and a fresh backup; retain the old
  generation and 17 data directory through validation.

## Cutover

1. Pause the network-arrivals timer and other database jobs and clients. The
   rehearsal found that network-arrivals can start PostgreSQL again while it
   is stopped; stopping PostgreSQL also stopped Forgejo. Ensure no deploy is
   in flight, take a fresh dump and off-host snapshot, and record service and
   configuration state.
2. Stop PostgreSQL 17 cleanly and verify it stays stopped. Initialise the 18
   directory as `postgres`, using the old cluster's locale, encoding, checksum
   setting and locale archive. Run the 18 `pg_upgrade --check` with both Nix
   package paths and matching socket settings, then run `pg_upgrade --copy`.
   Retain the 17 data directory for recovery.
3. Switch to the prebuilt PostgreSQL 18 NixOS generation, start PostgreSQL and
   dependent services, and resume paused timers. Confirm the actual server
   version and data directory, database and role access, key application
   workflows, exporter and backup health. Run the suggested statistics
   collection and any generated upgrade scripts that are applicable. Do not
   run the old-cluster deletion script during validation.
4. Run and verify a new PostgreSQL 18 backup and off-host snapshot. Retain the
   old cluster and fresh pre-upgrade backup until a later deliberate cleanup.

## Recovery

Before 18 accepts writes, stop it and activate the recorded 17 NixOS generation
and untouched 17 cluster, then restart dependent services and jobs. After 18
accepts writes, those writes are absent from the old cluster; choose whether
to fix 18 or accept/reconcile the lost changes before returning to 17. A NixOS
generation rollback alone does not migrate data backwards.

Upstream guidance: <https://www.postgresql.org/docs/18/pgupgrade.html> and
<https://www.postgresql.org/docs/18/release-18.html>.

## Cutover notes: 2026-11-21

- The 18.7 NixOS system was built in CI and staged before downtime. Both live
  and offline `pg_upgrade --check` passed, followed by a successful copy-mode
  upgrade. PostgreSQL stopped at 10:31:44 UTC and 18 was ready at 10:31:58.
- The 17 cluster remains in `/var/lib/postgresql/17`; its system closure is
  retained by the `postgres17-rollback` GC root. The old cluster does not
  include writes made after cutover. Do not run `delete_old_cluster.sh` until
  a later deliberate cleanup.
- A pre-upgrade logical dump and restic snapshot were made. Snapshot
  `976a8ed8` retains that dump in a separate `partridge-pg17-upgrade` host
  group, so regular daily pruning of Partridge snapshots does not discard it.
  Post-upgrade dump and restic snapshot `e461146b` succeeded; the dump's zstd
  integrity check passed and it identifies PostgreSQL 18.7.
- Staged missing-statistics and full analysis completed. Database and role
  access, matching collation versions, PostgreSQL exporter (`pg_up 1`),
  Grafana database health, Forgejo database health, exercise tracker health,
  active client connections and the network-arrivals job were checked. No
  systemd units were failed. These checks do not cover every application flow.
- PostgreSQL's disk had 4.2 GiB available with both clusters retained. The
  network-arrivals timer was paused during cutover because it can start the
  server, and Forgejo and other clients were restarted afterward.
