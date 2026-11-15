# Network arrivals

Partridge polls OPNsense's Dnsmasq leases and Hostwatch observations every 60s.
PostgreSQL `network_inventory` retains the registry and events independently of
Loki retention. Grafana → Ops → **Network arrivals** (`/d/network-arrivals`)
shows recent arrivals, identities first collected in the last 24h/7d, inventory,
collector freshness and the journal. There are no new-device notifications.

## Access and deployment

The NixOS module reuses the existing SOPS-encrypted OPNsense monitoring key,
rendered into a separate 0400 environment file for the collector's Unix user.
It does not expose keys to Grafana or node-exporter. No secret is in the store.

**Before deploying:** add `Interfaces: Hostwatch` and
`Services: Dnsmasq DNS/DHCP: Settings` to the existing `prometheus` OPNsense user.
Do not grant All pages or administrator membership. These built-in privileges
also cover service/settings operations: this key must not be described as a
strictly read-only credential. The collector itself only calls the two search
endpoints below; its POSTs paginate read operations, never change settings.
A dedicated key can replace this shared credential later by changing the SOPS
references. The PR does not modify permissions or deploy itself.

- `/api/dnsmasq/leases/search`
- `/api/hostdiscovery/service/search`

Ensure Hostwatch is enabled on LAN and UNTRUSTED in OPNsense. The collector
filters to those interface descriptions and the two configured IPv4 subnets;
WAN, IPv6 and fallback kernel neighbour rows are excluded. Router certificate
verification matches the existing exporter (self-signed certificate).

Merge and use the repository's normal Partridge deployment. Check:

```sh
systemctl status network-arrivals.timer
systemctl start network-arrivals.service
journalctl -u network-arrivals.service -n 10 --no-pager
cat /var/lib/network-arrivals/collector.prom
sudo -u grafana psql -d network_inventory -c 'SELECT count(*) FROM devices'
```

Both source reads must succeed before inventory changes. A failed first read
cannot seed the baseline. The first complete, nonempty snapshot seeds quietly;
future new MACs, zones and MAC/zone/address combinations create durable events.
Ordinary renewals and repeated polls do not. A crashed journal delivery can
replay the same `event_id`; the SQL event table remains authoritative.
Do not reset `collector_state` or drop the database during normal deployment.
The existing all-database PostgreSQL/restic backup includes this database.

A failed poll retains inventory and the last successful timestamp, sets
`network_arrivals_poll_success=0`, and fails its systemd unit. The dashboard
marks collection stale after 180s; missing metrics display no data. Existing
systemd failure monitoring applies, but there are no device alerts. Metrics
contain aggregate counts only, with three fixed event labels; MACs, IPs and
hostnames appear only in PostgreSQL and structured journal fields. Existing
Alloy ships that journal to Loki without new device labels (30-day retention).
Grafana has SELECT only; the collector cannot create/drop tables.

## Interpretation

An identity is a MAC, not a guaranteed physical device. Private/randomised MACs
remain separate; hostnames never auto-merge identities. `friendly_names` in
`network-arrivals.nix` optionally maps MACs to labels. First observed means first
collected by this service, not the original join time. The initial baseline can
include historical Hostwatch identities. Later polls use only Hostwatch activity
within ten minutes and unexpired DHCP leases. A lease/source observation is not
proof of being online. Disappearances are not arrivals and are not logged.

The Archer C9 bridge translates downstream ARP MACs. DHCP preserves clients'
original MACs and is preferred for identity. Hostwatch records under its wireless
MAC are accepted only for the Archer's own .2 address; other translated records
are discarded. A static-IP downstream client with no DHCP identity cannot be
identified reliably from these sources. Static clients directly visible to
Hostwatch are included. This is passive router observation, not active scanning.

## Tests

`nix build .#checks.x86_64-linux.network-arrivals` runs source/pagination/failure
checks and PostgreSQL integration tests in an isolated temporary cluster. It
covers quiet baselining, renewals, identity/zone/address events, bridge translation,
private MACs, expired leases, transaction rollback and durable delivery retries.
No production database or router mutation is involved.

API contracts: [Dnsmasq](https://docs.opnsense.org/development/api/core/dnsmasq.html),
[Hostdiscovery](https://docs.opnsense.org/development/api/core/hostdiscovery.html).
