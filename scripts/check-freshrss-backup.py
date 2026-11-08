import os
import pathlib
import re
import subprocess
import sys
import tarfile
import tempfile
import threading

# Pass the output of nix eval --raw
# .#nixosConfigurations.falcon.config.systemd.services.freshrss-sqlite-backup.script
script = pathlib.Path(sys.argv[1]).read_text()
script = script[script.index("timestamp=") :]
script = re.sub(r"/nix/store/[^/]+/bin/", "", script)
with tempfile.TemporaryDirectory(dir=".") as temporary:
    root = pathlib.Path(temporary).resolve()
    data = root / "data"
    backups = root / "backups"
    user = data / "users/edward"
    user.mkdir(parents=True)
    backups.mkdir()
    (data / "empty").mkdir()
    (user / "sqlite-backups").mkdir()
    for name in ["config.php", "db.sqlite", "log.txt"]:
        (user / name).write_text("original")
    (user / "sqlite-backups/export.sqlite").write_text("export")
    (data / "config.php").write_text("config")
    for i in range(10):
        path = backups / f"state-old-{i}.tar.gz"
        path.touch()
        os.utime(path, (i + 1, i + 1))
    run = script.replace("/var/lib/freshrss", str(data)).replace(
        "/var/backups/freshrss", str(backups)
    )
    stop = threading.Event()

    def churn():
        while not stop.is_set():
            (user / "log.txt").write_text("changing log")
            wal = user / "db.sqlite-wal"
            wal.touch()
            wal.unlink(missing_ok=True)

    writer = threading.Thread(target=churn)
    writer.start()
    try:
        subprocess.run(["bash", "-euo", "pipefail", "-c", run], check=True)
    finally:
        stop.set()
        writer.join()
    archives = list(backups.glob("state-*.tar.gz"))
    assert len(archives) == 8, archives
    archive = next(p for p in archives if "old" not in p.name)
    with tarfile.open(archive) as tar:
        names = tar.getnames()
        assert "./users/edward/config.php" in names
        assert "./empty" in names
        assert not any(
            "db.sqlite" in p or "log.txt" in p or "sqlite-backups" in p for p in names
        )
    assert archive.stat().st_mode & 0o777 == 0o600
    assert not list(backups.glob("*.tmp"))
    for status, recover, expected_calls in [(1, True, 2), (1, False, 3), (2, False, 1)]:
        target = root / f"case-{status}-{recover}"
        target.mkdir()
        counter = target / "calls"
        wrapper = f'''
        calls=0
        tar() {{
          calls=$((calls + 1))
          printf '%s' "$calls" > {counter}
          if [ "$calls" -eq 1 ] || [ "{recover}" = "False" ]; then
            return {status}
          fi
          command tar "$@"
        }}
        sleep() {{ :; }}
        '''
        result = subprocess.run(
            [
                "bash",
                "-euo",
                "pipefail",
                "-c",
                wrapper + run.replace(str(backups), str(target)),
            ]
        )
        assert (result.returncode == 0) == recover
        assert int(counter.read_text()) == expected_calls
        assert bool(list(target.glob("state-*.tar.gz"))) == recover
        assert not list(target.glob("*.tmp"))
    print(
        "PASS: active log/WAL churn, archive contents, empty directories, 0600 mode, retention eight, temp cleanup"
    )
