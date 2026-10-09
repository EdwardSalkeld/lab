# webtrees LAN trial on Partridge

This is an alternative to Gramps Web in PR #345. It adds one native PHP-FPM
pool, reusing Partridge's Nginx, PostgreSQL and encrypted Restic backups. There
are no OCI containers, Redis service or task worker. The FPM master remains
running, but its maximum two request workers exit after 30 idle seconds.

The pinned upstream release is webtrees 2.2.6 on PHP 8.4. App code is immutable
in the Nix store; settings, uploaded files and media live in
`/var/lib/webtrees/data`. Use the lab PR workflow to upgrade the package;
in-app code updates and installing modules into the app directory are not
supported. GEDCOM exports are available through webtrees, rather than Gramps
XML or Gramps Desktop sync.

After merge/deploy, open **http://10.4.1.30:5052/** from the home LAN. Follow
the upstream setup wizard, select PostgreSQL, and enter:

| Setting | Value |
| --- | --- |
| Server name | `/run/postgresql` |
| Port | `5432` |
| Database user | `webtrees` |
| Database password | leave blank |
| Database name | `webtrees` |
| Table prefix | leave the default `wt_` |

The PHP workers run as the dedicated `webtrees` Unix user, matching the
PostgreSQL role through local socket peer authentication. No password or SOPS
change is needed. The wizard creates the first administrator using the name,
email and password you choose. Complete this before adding family data.

Create a tree or import a GEDCOM through the browser. Before any future public
connection, review the site's registration and tree privacy settings; the
current endpoint is restricted to `10.4.1.0/24`, and the working Cloudflare
tunnel/hello-world services are unchanged. No public route is added.

Port 5052 and the database/state directories are distinct from Gramps' port
5050 and state. Both PRs are independent alternatives based on main; deploying
both for a comparison will require combining their import-list changes.

Nightly PostgreSQL dumps cover the database. The existing encrypted Restic
backup also includes the data directory (config, GEDCOM files and media).
Restore the database and data directory together; sessions are disposable.

Upstream: [requirements](https://webtrees.net/install/requirements/),
[installation](https://webtrees.net/install/),
[demo](https://dev.webtrees.net/demo-stable/).
