# webtrees LAN and tailnet trial on Partridge

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

After merge/deploy, connect your phone to Tailscale and open
**http://partridge.tailb35748.ts.net:5052/**. This works at home and away;
no exit node or subnet route is required. Partridge's tailnet IPv4 address is
`100.68.203.63` if you need a DNS diagnostic.

The direct home LAN endpoint **http://10.4.1.30:5052/** also remains reachable.
Run the first setup through the tailnet hostname and keep
`http://partridge.tailb35748.ts.net:5052` as the wizard's website URL: webtrees
uses that configured base URL for links and redirects, so setting it to the
LAN address would send phone navigation back to the LAN address.

This URL is a changeable setting, not an installation identity. When the
trial is ready to move behind the existing tunnel, change only `base_url` in
`/var/lib/webtrees/data/config.ini.php` to `https://family.salkeld.net` as part
of that cutover. No database rebuild, tree export/import or account recreation
is required. The explicit HTTPS base URL also makes generated links use HTTPS
when the tunnel connects to an HTTP origin. Users should open the new URL and
sign in again; browser cookies are specific to the hostname.

The tunnel cutover will separately need a local origin listener/allowlist and
the tunnel routing change. The current LAN/tailnet listener rejects loopback
clients, so changing the URL alone does not connect the tunnel. Keep the
working hello-world route until that later stage. webtrees uses one canonical
URL: after cutover, direct LAN/tailnet pages will generate links to the public
URL rather than provide an independent alternate site.

Follow the upstream setup wizard, select PostgreSQL, and enter:

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
current endpoint allows the home LAN (`10.4.1.0/24`) and Tailscale's IPv4/IPv6
address ranges (`100.64.0.0/10`, `fd7a:115c:a1e0::/48`). Tailnet access also
requires permission under the existing Tailscale policy; the personal phone
already has access to Partridge. The working Cloudflare
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
