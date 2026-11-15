"""Read OPNsense observations; retain identities, not a claim of physical presence."""

import base64
import datetime as dt
import ipaddress
import json
import os
from pathlib import Path
import re
import ssl
import sys
import urllib.request

UTC = dt.timezone.utc
KINDS = ("new_identity", "new_zone", "new_address")


class API:
    def __init__(self, config):
        self.base = config["url"].rstrip("/")
        self.auth = (
            "Basic "
            + base64.b64encode(
                (
                    os.environ["OPNSENSE_API_KEY"]
                    + ":"
                    + os.environ["OPNSENSE_API_SECRET"]
                ).encode()
            ).decode()
        )
        self.context = (
            ssl.create_default_context()
            if config.get("verify_tls", True)
            else ssl._create_unverified_context()
        )

    def page(self, path, page):
        body = json.dumps({"current": page, "rowCount": 500}).encode()
        request = urllib.request.Request(
            self.base + "/api/" + path,
            data=body,
            headers={"Authorization": self.auth, "Content-Type": "application/json"},
        )
        with urllib.request.urlopen(
            request, context=self.context, timeout=15
        ) as response:
            return json.load(response)

    def rows(self, path):
        rows = []
        expected = None
        for page in range(1, 101):
            data = self.page(path, page)
            if not isinstance(data.get("rows"), list) or "total" not in data:
                raise ValueError("Invalid API search response: " + path)
            total = int(data["total"])
            if expected is not None and total != expected:
                raise ValueError(
                    "API snapshot changed during pagination; retry next poll"
                )
            expected = total
            batch = data["rows"]
            rows.extend(batch)
            if len(rows) == total:
                return rows
            if not batch or len(rows) > total:
                break
        raise ValueError("Incomplete API snapshot: " + path)


def timestamp(value):
    if value in (None, "", "never", "Never", "infinite", 0, "0"):
        return None
    try:
        return dt.datetime.fromtimestamp(float(value), UTC)
    except (ValueError, TypeError):
        # OPNsense renders some timestamps as ISO dates without an offset.
        parsed = dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            raise ValueError("Timestamp has no timezone: " + str(value))
        return parsed.astimezone(UTC)


def identity(value):
    value = str(value).lower().replace("-", ":")
    if not re.fullmatch(r"(?:[0-9a-f]{2}:){5}[0-9a-f]{2}", value):
        return None
    if value == "00:00:00:00:00:00" or int(value[:2], 16) & 1:
        return None
    return value


def observations(leases, hosts, config, now, baseline):
    zones = [
        (name, ipaddress.ip_network(cidr)) for name, cidr in config["zones"].items()
    ]
    translated = config.get("translated_macs", {})
    result = {}

    def add(mac, address, source, hostname="", vendor="", activity=None, expires=None):
        mac = identity(mac)
        try:
            address = ipaddress.ip_address(address)
        except ValueError:
            return
        zone = next((name for name, net in zones if address in net), None)
        if not mac or not zone:
            return
        key = (mac, zone, str(address))
        old = result.get(key)
        if old and old["source"] == "dhcp":
            old["activity"] = activity
            old["vendor"] = old["vendor"] or vendor or ""
            return
        result[key] = dict(
            mac=mac,
            zone=zone,
            address=str(address),
            source=source,
            hostname=(hostname or "") if hostname != "*" else "",
            vendor=vendor or "",
            activity=activity,
            expires=expires,
        )

    for row in leases:
        expiry = timestamp(row.get("expire"))
        if expiry is not None and expiry <= now:
            continue
        if not identity(row.get("hwaddr")):
            continue
        add(
            row["hwaddr"],
            row["address"],
            "dhcp",
            row.get("hostname", ""),
            row.get("mac_info", ""),
            expires=expiry,
        )
    for row in hosts:
        mac, address = row.get("ether_address"), row.get("ip_address")
        if row.get("source") != "discovery":
            continue
        if row.get("interface_name") not in config.get(
            "interfaces", ["LAN", "UNTRUSTED"]
        ):
            continue
        activity = timestamp(row.get("last_seen"))
        # A translated bridge MAC is not the identity of each downstream client.
        if identity(mac) in translated and address not in translated[identity(mac)]:
            continue
        if not baseline and (
            activity is None or (now - activity).total_seconds() > 600
        ):
            continue
        add(
            mac,
            address,
            "hostwatch",
            vendor=row.get("organization_name", ""),
            activity=activity,
        )
    return sorted(
        result.values(), key=lambda row: (row["mac"], row["zone"], row["address"])
    )


def save(connection, rows, now, names):
    """One transaction: inventory, baseline marker and durable event outbox."""
    with connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT pg_advisory_xact_lock(27182020)")
            cursor.execute(
                "SELECT initialized FROM collector_state WHERE id = 1 FOR UPDATE"
            )
            initialized = cursor.fetchone()[0]
            for row in rows:
                mac, zone, address = row["mac"], row["zone"], row["address"]
                cursor.execute("SELECT 1 FROM devices WHERE mac = %s", (mac,))
                new_device = cursor.fetchone() is None
                cursor.execute(
                    "INSERT INTO devices(mac, first_observed, last_observed, friendly_name, hostname, vendor) "
                    "VALUES (%s,%s,%s,%s,%s,%s) ON CONFLICT(mac) DO UPDATE SET "
                    "last_observed=EXCLUDED.last_observed, friendly_name=EXCLUDED.friendly_name, "
                    "hostname=COALESCE(NULLIF(EXCLUDED.hostname,''),devices.hostname), "
                    "vendor=COALESCE(NULLIF(EXCLUDED.vendor,''),devices.vendor)",
                    (mac, now, now, names.get(mac, ""), row["hostname"], row["vendor"]),
                )
                cursor.execute(
                    "SELECT 1 FROM observations WHERE mac=%s AND zone=%s", (mac, zone)
                )
                new_zone = cursor.fetchone() is None
                cursor.execute(
                    "SELECT 1 FROM observations WHERE mac=%s AND zone=%s AND address=%s::inet",
                    (mac, zone, address),
                )
                new_address = cursor.fetchone() is None
                cursor.execute(
                    "INSERT INTO observations(mac,zone,address,source,first_observed,last_observed,last_activity,lease_expires) "
                    "VALUES (%s,%s,%s::inet,%s,%s,%s,%s,%s) ON CONFLICT(mac,zone,address) DO UPDATE SET "
                    "last_observed=EXCLUDED.last_observed,source=EXCLUDED.source, "
                    "last_activity=GREATEST(observations.last_activity,EXCLUDED.last_activity), "
                    "lease_expires=EXCLUDED.lease_expires",
                    (
                        mac,
                        zone,
                        address,
                        row["source"],
                        now,
                        now,
                        row["activity"],
                        row["expires"],
                    ),
                )
                kind = (
                    "new_identity"
                    if new_device
                    else "new_zone"
                    if new_zone
                    else "new_address"
                    if new_address
                    else None
                )
                if initialized and kind:
                    cursor.execute(
                        "INSERT INTO events(observed_at,kind,mac,zone,address,source,hostname) "
                        "VALUES (%s,%s,%s,%s,%s::inet,%s,%s)",
                        (now, kind, mac, zone, address, row["source"], row["hostname"]),
                    )
            if not initialized and not rows:
                raise ValueError("Refusing to seed an empty baseline")
            cursor.execute(
                "UPDATE collector_state SET initialized=true,last_success=%s WHERE id=1",
                (now,),
            )


def publish(connection, emit=print):
    # At-least-once journal delivery. event_id lets consumers recognise replay.
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT id,observed_at,kind,mac,zone,host(address),source,hostname FROM events WHERE NOT published ORDER BY id"
        )
        pending = cursor.fetchall()
    for event in pending:
        payload = dict(
            zip(
                (
                    "event_id",
                    "observed_at",
                    "event",
                    "mac",
                    "zone",
                    "address",
                    "source",
                    "hostname",
                ),
                event,
            )
        )
        payload["observed_at"] = payload["observed_at"].isoformat()
        emit(json.dumps(payload), flush=True)
        with connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    "UPDATE events SET published=true WHERE id=%s", (event[0],)
                )


def metrics(path, success, connection=None):
    path = Path(path)
    previous = path.read_text().splitlines() if path.exists() else []
    lines = [
        line
        for line in previous
        if not line.startswith("network_arrivals_poll_success ")
    ]
    if success:
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT extract(epoch FROM last_success) FROM collector_state WHERE id=1"
            )
            last = cursor.fetchone()[0]
            cursor.execute("SELECT count(*) FROM devices")
            count = cursor.fetchone()[0]
            cursor.execute("SELECT kind,count(*) FROM events GROUP BY kind")
            counts = dict(cursor.fetchall())
        lines = [
            f"network_arrivals_last_success_timestamp_seconds {last}",
            f"network_arrivals_identities {count}",
        ]
        lines.extend(
            f'network_arrivals_events_total{{event="{kind}"}} {counts.get(kind, 0)}'
            for kind in KINDS
        )
    lines.append(f"network_arrivals_poll_success {int(success)}")
    temporary = path.with_suffix(".tmp")
    temporary.write_text("\n".join(lines) + "\n")
    temporary.replace(path)


def main():
    import psycopg2

    config = json.loads(Path(sys.argv[1]).read_text())
    try:
        api = API(config)
        # Never commit a partial snapshot or treat a failed source as an empty list.
        leases = api.rows("dnsmasq/leases/search")
        hosts = api.rows("hostdiscovery/service/search")
        now = dt.datetime.now(UTC)
        with psycopg2.connect(config["database"], connect_timeout=10) as connection:
            with connection.cursor() as cursor:
                cursor.execute("SELECT initialized FROM collector_state WHERE id=1")
                baseline = not cursor.fetchone()[0]
            rows = observations(leases, hosts, config, now, baseline)
            save(connection, rows, now, config.get("friendly_names", {}))
            publish(connection)
            metrics(config["metrics_path"], True, connection)
        print(
            json.dumps(
                {
                    "event": "poll_complete",
                    "observations": len(rows),
                    "baseline": baseline,
                }
            ),
            flush=True,
        )
    except Exception as error:
        metrics(config["metrics_path"], False)
        # HTTPError text includes status, but never response bodies or credentials.
        print(
            json.dumps({"event": "poll_failed", "error": str(error)}),
            file=sys.stderr,
            flush=True,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
