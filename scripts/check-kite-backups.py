#!/usr/bin/env python3
"""Check enabled backup configuration, archive continuity and disk guards."""
import json
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[1]
data = json.loads(subprocess.check_output([
    "nix", "eval", "--json", f"{root}#nixosConfigurations.kite.config", "--apply", """
    cfg: {
      enabled = cfg.alcachofa.kite.backups.enable;
      backup = cfg.services.restic.backups.kite-full;
      prune = cfg.services.restic.backups.kite-full-prune;
      check = cfg.services.restic.backups.kite-full-check;
      unit = cfg.systemd.services.restic-backups-kite-full.unitConfig;
      bind = cfg.systemd.services.restic-backups-kite-full.serviceConfig.BindReadOnlyPaths;
      pruneGuard = cfg.systemd.services.restic-backups-kite-full-prune.unitConfig.ConditionPathExists;
    }
    """,
], text=True))
assert data["enabled"]
backup = data["backup"]
assert backup["paths"] == ["/mnt/volumes"]
assert set(backup["extraBackupArgs"]) == {"--host=docker", "--tag=dataplan", "--verbose"}
assert backup["exclude"] == ["*.tmp"]
assert not backup["initialize"] and backup["pruneOpts"] == []
assert data["bind"] == ["/data/full:/mnt/volumes"]
assert "/data" in data["unit"]["RequiresMountsFor"]
assert data["unit"]["AssertPathIsMountPoint"] == "/data"
prune = data["prune"]
assert set(prune["pruneOpts"]) == {
    "--host docker", "--path /mnt/volumes", "--tag dataplan",
    "--keep-last 3", "--keep-daily 7", "--keep-weekly 5", "--keep-monthly 12",
}
assert not prune["timerConfig"]["Persistent"]
assert data["pruneGuard"] == "/var/lib/kite-backup/verified"
assert data["check"]["checkOpts"] == ["--read-data-subset=10%"]
assert data["check"]["runCheck"]
for job, calendar in (
    (backup, "Mon *-*-* 06:30:00 Europe/London"),
    (prune, "Tue *-*-* 04:00:00 Europe/London"),
    (data["check"], "Wed *-*-* 05:15:00 Europe/London"),
):
    assert job["timerConfig"]["OnCalendar"] == calendar
    assert job["environmentFile"] == "/run/secrets/rendered/kite-backup-restic.env"
secret = (root / "nixos/hosts/kite/secrets/kite-backup.yaml").read_text()
for key in ("restic_repository", "restic_password", "b2_account_id", "b2_account_key"):
    assert re.search(rf"^{key}: ENC\[AES256_GCM,", secret, re.M), key
print("Kite backup continuity, encrypted credentials, mount and retention guards passed")
