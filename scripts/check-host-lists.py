#!/usr/bin/env python3
"""Check fourth's fixed host allowlists and the nix-gc choices match the flake."""

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
flake_hosts = sorted(
    json.loads(
        subprocess.check_output(
            [
                "nix",
                "eval",
                "--json",
                f"{root}#nixosConfigurations",
                "--apply",
                "builtins.attrNames",
            ],
            text=True,
        )
    )
)
failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def allowlist(script):
    match = re.search(r"^HOSTS=\(\n(.*?)^\)", script.read_text(), re.M | re.S)
    assert match, f"{script}: no HOSTS=( ... ) list"
    return match.group(1).split()


fqdns = allowlist(root / "deploy/nix-switch.sh")
check(
    sorted(f.split(".", 1)[0] for f in fqdns) == flake_hosts,
    f"deploy/nix-switch.sh HOSTS {fqdns} do not match the flake's {flake_hosts}",
)
check(
    allowlist(root / "deploy/nix-gc.sh") == fqdns,
    "deploy/nix-gc.sh HOSTS differ from deploy/nix-switch.sh",
)

for host in flake_hosts:
    wrapper = root / f"deploy/nix-gc-{host}.sh"
    check(
        wrapper.is_file()
        and os.access(wrapper, os.X_OK)
        and f'exec "$(dirname "$0")/nix-gc.sh" {host}\n' in wrapper.read_text(),
        f"{wrapper.relative_to(root)} is missing or does not run nix-gc.sh {host}",
    )

workflow = (root / ".github/workflows/nix-gc.yml").read_text()
options = re.search(r"^ +options:\n((?: +- .*\n)+)", workflow, re.M)
check(
    options is not None
    and sorted(re.findall(r"- (\S+)", options.group(1))) == flake_hosts,
    f"nix-gc.yml host options do not match the flake's {flake_hosts}",
)

store = "/nix/store/" + "a" * 32 + "-nixos-system-"
sha = "c" * 40
prefix = f"nix-switch {sha} lab-cache lab-cache.cachix.org-1:abc="
pairs = [f"{h}={store}{h}" for h in flake_hosts]

with tempfile.TemporaryDirectory(prefix="check-host-lists-") as directory:
    temp = Path(directory)
    log = temp / "calls"
    for name in ("ssh", "git"):
        stub = temp / name
        stub.write_text(
            f'#!/usr/bin/env bash\nprintf \'{name} %s\\n\' "$*" >> "$TEST_LOG"\n'
        )
        stub.chmod(0o755)

    def run(script, command="", *args):
        log.write_text("")
        result = subprocess.run(
            [root / "deploy" / script, *args],
            env={
                **os.environ,
                "PATH": f"{temp}:{os.environ['PATH']}",
                "TEST_LOG": str(log),
                "ONWARD_SSH_KEY": "key",
                "SSH_ORIGINAL_COMMAND": command,
            },
            capture_output=True,
            text=True,
        )
        ssh = [line for line in log.read_text().splitlines() if line.startswith("ssh ")]
        return result.returncode, ssh

    rc, ssh = run("nix-switch.sh", " ".join([prefix, *reversed(pairs)]))
    check(rc == 0, f"nix-switch.sh rejected a request for every host: {rc}")
    check(
        len(ssh) == len(fqdns)
        and all(
            f"root@{fqdn} lab-switch {sha}" in got
            and got.endswith(f"{store}{fqdn.split('.', 1)[0]}")
            for fqdn, got in zip(fqdns, ssh)
        ),
        f"nix-switch.sh did not switch each host to its own path: {ssh}",
    )

    refused = {
        "missing host": pairs[1:],
        "repeated host": [*pairs, pairs[0]],
        "unknown host": [*pairs, f"wren={store}wren"],
        "bad path": [*pairs[1:], f"{flake_hosts[0]}=/tmp/x"],
        "positional paths": [f"{store}{h}" for h in flake_hosts],
    }
    for case, request in refused.items():
        rc, ssh = run("nix-switch.sh", " ".join([prefix, *request]))
        check(rc == 2 and not ssh, f"nix-switch.sh accepted {case}: rc={rc} {ssh}")

    for fqdn in fqdns:
        host = fqdn.split(".", 1)[0]
        if not os.access(root / f"deploy/nix-gc-{host}.sh", os.X_OK):
            continue
        rc, ssh = run(f"nix-gc-{host}.sh")
        check(
            rc == 0 and ssh and ssh[0].endswith(f"root@{fqdn} nix-gc"),
            f"nix-gc-{host}.sh did not collect on {fqdn}: rc={rc} {ssh}",
        )
    rc, ssh = run("nix-gc.sh", "", "wren")
    check(rc == 2 and not ssh, f"nix-gc.sh accepted an unknown host: {ssh}")

if failures:
    raise SystemExit("\n".join(failures))
print(f"host lists match the flake: {' '.join(flake_hosts)}")
