import datetime as dt
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import collector as c

NOW = dt.datetime(2026, 11, 15, tzinfo=c.UTC)
CONFIG = {
    "zones": {"trusted": "10.4.1.0/24", "untrusted": "10.4.20.0/24"},
    "translated_macs": {"c4:e9:84:6e:02:dc": ["10.4.1.2"]},
}
MAC = "02:11:22:33:44:55"


def lease(mac=MAC, address="10.4.1.70", **kwargs):
    return dict(
        hwaddr=mac,
        address=address,
        expire=int(NOW.timestamp()) + 21600,
        hostname="thermostat",
        **kwargs,
    )


def host(mac=MAC, address="10.4.1.70", age=0):
    return dict(
        source="discovery",
        interface_name="LAN",
        ether_address=mac,
        ip_address=address,
        last_seen=(NOW - dt.timedelta(seconds=age)).isoformat(),
        organization_name="Vendor",
    )


class Sources(unittest.TestCase):
    def test_bridge_and_expired_lease(self):
        expired = lease(address="10.4.1.71")
        expired["expire"] = NOW.timestamp() - 1
        rows = c.observations(
            [lease(), expired], [host("c4:e9:84:6e:02:dc")], CONFIG, NOW, False
        )
        self.assertEqual([(r["mac"], r["source"]) for r in rows], [(MAC, "dhcp")])

    def test_history_not_replayed_as_current_and_private_macs_distinct(self):
        self.assertEqual(c.observations([], [host(age=601)], CONFIG, NOW, False), [])
        self.assertEqual(len(c.observations([], [host(age=601)], CONFIG, NOW, True)), 1)
        self.assertEqual(
            len(
                c.observations(
                    [lease(), lease("02:11:22:33:44:56")], [], CONFIG, NOW, False
                )
            ),
            2,
        )
        self.assertIsNone(c.identity("ff:ff:ff:ff:ff:ff"))

    def test_nullable_vendor_and_wan_rows(self):
        row = host()
        row["organization_name"] = None
        rows = c.observations([], [row], CONFIG, NOW, True)
        self.assertEqual(rows[0]["vendor"], "")
        row["interface_name"] = "WAN"
        self.assertEqual(c.observations([], [row], CONFIG, NOW, True), [])
        row["interface_name"] = "LAN"
        row["source"] = "kernel"
        self.assertEqual(c.observations([], [row], CONFIG, NOW, True), [])

    def test_pagination_and_failure(self):
        api = object.__new__(c.API)
        with patch.object(
            api,
            "page",
            side_effect=[{"rows": [1], "total": 2}, {"rows": [2], "total": 2}],
        ):
            self.assertEqual(api.rows("test"), [1, 2])
        with patch.object(
            api,
            "page",
            side_effect=[{"rows": [1], "total": 2}, {"rows": [], "total": 2}],
        ):
            with self.assertRaises(ValueError):
                api.rows("test")
        with patch.object(api, "page", return_value={"message": "Forbidden"}):
            with self.assertRaises(ValueError):
                api.rows("test")

    def test_failure_preserves_last_success_metric(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "collector.prom"
            path.write_text(
                "network_arrivals_last_success_timestamp_seconds 123\nnetwork_arrivals_poll_success 1\n"
            )
            c.metrics(path, False)
            self.assertIn("timestamp_seconds 123", path.read_text())
            self.assertIn("poll_success 0", path.read_text())


@unittest.skipUnless(
    os.getenv("TEST_DATABASE"), "Set TEST_DATABASE for PostgreSQL integration tests"
)
class Database(unittest.TestCase):
    def setUp(self):
        import psycopg2

        self.db = psycopg2.connect(os.environ["TEST_DATABASE"])
        with self.db:
            with self.db.cursor() as cursor:
                cursor.execute("DROP SCHEMA public CASCADE; CREATE SCHEMA public")
                cursor.execute(Path(__file__).with_name("schema.sql").read_text())

    def tearDown(self):
        self.db.close()

    def counts(self):
        with self.db.cursor() as cursor:
            cursor.execute("SELECT kind,count(*) FROM events GROUP BY kind")
            return dict(cursor.fetchall())

    def save(self, leases):
        c.save(self.db, c.observations(leases, [], CONFIG, NOW, False), NOW, {})

    def test_baseline_renewals_new_identity_zone_and_address(self):
        self.save([lease()])
        self.assertEqual(self.counts(), {})
        renewed = lease()
        renewed["expire"] += 100
        self.save([renewed])
        self.assertEqual(self.counts(), {})
        self.save([lease(), lease("02:11:22:33:44:56")])
        self.save([lease(address="10.4.20.70")])
        self.save([lease(address="10.4.20.71")])
        self.save([lease(address="10.4.20.71")])
        self.assertEqual(self.counts(), dict(new_identity=1, new_zone=1, new_address=1))
        emitted = []
        c.publish(self.db, lambda text, **_: emitted.append(json.loads(text)))
        c.publish(self.db, lambda text, **_: emitted.append(json.loads(text)))
        self.assertEqual(len(emitted), 3)
        self.assertEqual(len({r["event_id"] for r in emitted}), 3)

    def test_failed_initialization_and_outbox_recovery(self):
        with self.assertRaises(ValueError):
            self.save([])
        self.save([lease()])
        self.save([lease("02:11:22:33:44:56")])

        def failed_emit(*args, **kwargs):
            raise OSError("journal unavailable")

        with self.assertRaises(OSError):
            c.publish(self.db, failed_emit)
        emitted = []
        c.publish(self.db, lambda text, **_: emitted.append(text))
        self.assertEqual(len(emitted), 1)


if __name__ == "__main__":
    unittest.main()
