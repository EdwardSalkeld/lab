"""Exercise the real watchdog with isolated paths and mocked host commands."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


WATCHDOG = Path(__file__).resolve().parents[1] / "luna-network-watchdog"
MOCK = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

root = Path(os.environ["WATCHDOG_TEST_ROOT"])
name = Path(sys.argv[0]).name
settings = json.loads((root / "settings.json").read_text())
with (root / "commands.jsonl").open("a") as log:
    log.write(json.dumps([name, *sys.argv[1:]]) + "\n")
if name == "date":
    print(settings["now"] if sys.argv[-1] == "+%s" else "20261012T200000Z")
elif name == "ping":
    after_reset = (root / "reset").exists()
    probes = settings["after"] if after_reset else settings["before"]
    sys.exit(0 if probes[sys.argv[-1]] else 1)
elif name == "ip" and sys.argv[1:3] == ["link", "set"]:
    (root / "reset").touch()
elif name == "systemctl":
    sys.exit(settings["reboot_status"])
'''


class WatchdogTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.state = self.root / "state"
        self.state.mkdir()
        self.settings = {
            "now": 200000,
            "before": {"10.4.1.1": False, "1.1.1.1": False},
            "after": {"10.4.1.1": False, "1.1.1.1": False},
            "reboot_status": 0,
        }
        script = WATCHDOG.read_text()
        for variable, path in {
            "config_file": self.root / "config",
            "state_dir": self.state,
            "log_dir": self.root / "logs",
            "lock_file": self.root / "lock",
        }.items():
            lines = script.splitlines()
            script = "\n".join(
                f"readonly {variable}={path}" if line.startswith(f"readonly {variable}=")
                else line for line in lines
            ) + "\n"
        self.script = self.root / "watchdog"
        self.script.write_text(script)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for command in ("ping", "ip", "ethtool", "journalctl", "logger", "date", "sleep", "systemctl", "sync"):
            mock = self.bin / command
            mock.write_text(MOCK)
            mock.chmod(0o755)

    def run_watchdog(self):
        (self.root / "settings.json").write_text(json.dumps(self.settings))
        result = subprocess.run(
            ["bash", str(self.script)],
            env={**os.environ, "PATH": f"{self.bin}:{os.environ['PATH']}",
                 "WATCHDOG_TEST_ROOT": str(self.root)},
            capture_output=True, text=True, timeout=10,
        )
        self.assertIn(result.returncode, (0, 1), result.stderr)
        return result.returncode

    def commands(self):
        path = self.root / "commands.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def recovery_commands(self):
        return [cmd for cmd in self.commands()
                if cmd[0] == "systemctl" or cmd[:3] == ["ip", "link", "set"]]

    def threshold(self):
        for _ in range(3):
            self.run_watchdog()

    def test_either_probe_reachable_prevents_recovery_and_clears_failures(self):
        for gateway, external in ((True, True), (True, False), (False, True)):
            with self.subTest(gateway=gateway, external=external):
                (self.state / "consecutive_failures").write_text("5\n")
                self.settings["before"] = {"10.4.1.1": gateway, "1.1.1.1": external}
                self.assertEqual(self.run_watchdog(), 0)
                self.assertFalse((self.state / "consecutive_failures").exists())
                self.assertEqual(self.recovery_commands(), [])

    def test_dual_failure_threshold_reset_then_reboot(self):
        for _ in range(2):
            self.assertEqual(self.run_watchdog(), 0)
            self.assertEqual(self.recovery_commands(), [])
        self.assertEqual(self.run_watchdog(), 0)
        recovery = self.recovery_commands()
        self.assertEqual([cmd[-1] for cmd in recovery[:2]], ["down", "up"])
        self.assertEqual(recovery[2][:2], ["systemctl", "reboot"])
        self.assertEqual(len(recovery), 3)
        self.assertTrue(list((self.root / "logs").glob("*-network-failure.log")))
        self.assertEqual((self.state / "last_automatic_recovery_epoch").read_text().strip(), "200000")

    def test_repeated_failures_are_capped_until_expiry(self):
        self.threshold()
        original = self.recovery_commands()
        for _ in range(3):
            self.assertEqual(self.run_watchdog(), 1)
        self.assertEqual(self.recovery_commands(), original)
        self.settings["now"] += 86400
        self.assertEqual(self.run_watchdog(), 0)
        self.assertEqual(len(self.recovery_commands()), 6)

    def test_existing_reboot_cap_prevents_first_reset_after_upgrade(self):
        (self.state / "last_automatic_reboot_epoch").write_text("199999\n")
        self.threshold()
        self.assertEqual(self.recovery_commands(), [])
        self.assertEqual(self.run_watchdog(), 1)

    def test_recovery_on_either_probe_avoids_reboot_and_remains_capped(self):
        for address in ("10.4.1.1", "1.1.1.1"):
            with self.subTest(address=address):
                for path in self.state.iterdir():
                    path.unlink()
                (self.root / "commands.jsonl").unlink(missing_ok=True)
                (self.root / "reset").unlink(missing_ok=True)
                self.settings["after"] = {"10.4.1.1": False, "1.1.1.1": False}
                self.settings["after"][address] = True
                self.threshold()
                self.assertEqual(len(self.recovery_commands()), 2)
                self.assertFalse((self.state / "consecutive_failures").exists())
                (self.root / "reset").unlink()
                self.threshold()
                self.assertEqual(len(self.recovery_commands()), 2)

    def test_failed_reboot_request_does_not_allow_more_resets(self):
        self.settings["reboot_status"] = 1
        self.threshold()
        self.assertEqual(len(self.recovery_commands()), 3)
        self.assertEqual(self.run_watchdog(), 1)
        self.assertEqual(len(self.recovery_commands()), 3)

    def test_healthy_interval_does_not_clear_persistent_cap(self):
        self.threshold()
        self.settings["before"]["10.4.1.1"] = True
        self.settings["after"]["10.4.1.1"] = True
        self.assertEqual(self.run_watchdog(), 0)
        self.settings["before"]["10.4.1.1"] = False
        self.settings["after"]["10.4.1.1"] = False
        self.threshold()
        self.assertEqual(len(self.recovery_commands()), 3)


if __name__ == "__main__":
    unittest.main()
