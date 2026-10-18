# Gramps Web on Partridge (stage 2)

After the lab PR is merged and deployed, open **http://10.4.1.30:5050/** from
the home LAN. The first-run wizard creates the owner's account; choose your
own username/password. It can import a Gramps XML (`.gramps`) export, or you
can start with the empty **Salkeld family** tree. Ordinary self-registration
is disabled; the owner can add accounts later. SMTP is not configured yet,
so password-reset emails are not available at this stage.

Only Partridge's LAN address listens on port 5050, and Nginx accepts clients
from `10.4.1.0/24`. The API listens on `127.0.0.1:5051`. Neither the tunnel
nor its temporary hello-world origin changes; `family.salkeld.net` continues
to show the stage 1 page until stage 3 is requested.

The pinned upstream Gramps Web 26.10.0 image runs under NixOS-managed Podman,
with one Gunicorn worker and one Celery worker to fit Partridge's 4 GiB RAM.
Redis listens on loopback port 6381 for the task queue and rate limiting.
The containers share the host network to reach loopback PostgreSQL/Redis;
no container publishes a port. SOPS supplies the Flask secret and database
password through a root-only environment file outside the Nix store.

The existing PostgreSQL 17 service owns two additional databases:

- `gramps`: genealogical records using **SharedPostgreSQL**, plus search index.
- `grampswebuser`: accounts, permissions and app settings.

The `gramps` role owns both databases and authenticates with SCRAM from
loopback only. Before the web container starts, a small idempotent bootstrap
creates the PostgreSQL tree with a fixed UUID, verifies its backend, and opens
its schema. Normal operation uses single-tree mode with `TREE_ID`, so the app
does not silently create a SQLite tree. The bootstrap uses the pinned API's
`WebDbManager`; run the smoke test when upgrading the image.

Persistent tree metadata is under `/var/lib/gramps-web/db`, and uploaded media
under `/var/lib/gramps-web/media`. Both are included in Partridge's existing
encrypted off-host Restic backup. The nightly all-database PostgreSQL dump
includes both new databases and role credentials. Restoring the installation
requires the PostgreSQL dump, tree metadata and media from the same backup
period, plus the SOPS secrets in lab. A `.gramps` export is also available from
the app; export media separately or use the package export for portability.
Thumbnail/report caches and temporary files can be regenerated.

Useful service names:

- `gramps-web-db-setup.service`
- `podman-gramps-web.service`
- `podman-gramps-web-worker.service`
- `redis-gramps-web.service`

`scripts/check-gramps-web.py` tests the evaluated container configuration on an
isolated Docker-enabled runner: initial and repeated bootstrap, owner setup,
creating a person in PostgreSQL, a Celery export, and persistence across restart.
It runs in the dedicated Gramps Web PR workflow, with disposable credentials.

Upstream setup references:
[PostgreSQL](https://www.grampsweb.org/install_setup/postgres/),
[Docker](https://www.grampsweb.org/install_setup/deployment/).
