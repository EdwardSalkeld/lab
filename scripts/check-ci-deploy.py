#!/usr/bin/env python3
"""Exercise deployment refusal and recovery paths without changing a host."""

import json
import os
import re
from pathlib import Path
import subprocess
import tempfile


def output(*args):
    return subprocess.check_output(args, text=True).strip()


root = Path(__file__).resolve().parents[1]
context = json.loads(
    output(
        "nix",
        "eval",
        "--json",
        f"{root}#nixosConfigurations.partridge.config.users.users.root.openssh.authorizedKeys.keys",
        "--apply",
        "keys: builtins.getContext (builtins.head keys)",
    )
)
remote_drv = next(iter(context))


def derivation(path):
    data = json.loads(output("nix", "derivation", "show", path))
    return next(iter(data.get("derivations", data).values()))


remote = derivation(remote_drv)
inputs = remote.get("inputDrvs", remote.get("inputs", {}).get("drvs", {}))
switch_drv = next(p for p in inputs if p.endswith("-lab-switch.drv"))
if not switch_drv.startswith("/"):
    switch_drv = "/nix/store/" + switch_drv
switch = derivation(switch_drv)["env"]["text"]
bootstrap = (root / "scripts/bootstrap-ci-deploy.sh").read_text()
expected = "/nix/store/" + "a" * 32 + "-nixos-system-partridge"
previous = "/nix/store/" + "b" * 32 + "-nixos-system-partridge"
sha = "c" * 40
config = json.loads(
    output(
        "nix",
        "eval",
        "--json",
        f"{root}#nixosConfigurations.partridge.config.alcachofa.remoteDeploy",
    )
)
cache = config["cacheName"]
key = config["cachePublicKey"]

with tempfile.TemporaryDirectory(prefix="check-ci-deploy-") as directory:
    temp = Path(directory)
    log = temp / "calls"
    stub = temp / "stub"
    stub.write_text("""#!/usr/bin/env bash
name=${0##*/}
printf '%s' "$name" >> "$TEST_LOG"
printf ' %s' "$@" >> "$TEST_LOG"
printf '\\n' >> "$TEST_LOG"
case "$name" in
  nix)
    if [[ "$1" == eval && "$*" == *toplevel.outPath* ]]; then
      printf '%s\\n' "$TEST_PATH"
    fi
    ;;
  nix-store)
    [[ "${TEST_FETCH_FAIL:-0}" == 0 ]] || exit 1
    [[ "$*" != *--add-root* || "${TEST_PIN_FAIL:-0}" == 0 ]] || exit 1
    ;;
  nix-env) [[ "${TEST_PROFILE_FAIL:-0}" == 0 ]] || exit 1 ;;
  nixos-rebuild)
    # The old recovery command fails on flake-only hosts, as in production.
    [[ "$*" != *--rollback* ]] || exit 1
    [[ "${TEST_SWITCH_FAIL:-0}" == 0 ]] || exit 1
    ;;
  systemctl)
    if [[ "$1" == is-active ]]; then
      [[ "${TEST_HEALTH_FAIL:-0}" == 0 ]] || exit 1
      if [[ "${TEST_HEALTH_UNTIL_RECOVERY:-0}" == 1 ]]; then
        [[ "$(< "$TEST_LOG")" == *"restore switch"* ]] || exit 1
      fi
    fi
    ;;
  curl) [[ "${TEST_HTTP_FAIL:-0}" == 0 ]] || exit 1 ;;
  flock) [[ "${TEST_LOCK_FAIL:-0}" == 0 ]] || exit 1 ;;
  activate) [[ "${TEST_SWITCH_FAIL:-0}" == 0 ]] || exit 1 ;;
  restore) [[ "${TEST_RECOVERY_FAIL:-0}" == 0 ]] || exit 1 ;;
  hostname) echo partridge ;;
  readlink)
    [[ "${TEST_READLINK_FAIL:-0}" == 0 ]] || exit 1
    echo "$TEST_PREVIOUS"
    ;;
esac
""")
    stub.chmod(0o755)
    for name in (
        "nix",
        "nix-store",
        "nix-env",
        "nixos-rebuild",
        "systemctl",
        "curl",
        "flock",
        "activate",
        "restore",
        "hostname",
        "readlink",
    ):
        (temp / name).symlink_to(stub)
    scripts = {}
    for name, text in (("switch", switch), ("bootstrap", bootstrap)):
        text = text.replace("/run/current-system/sw/bin/", f"{temp}/")
        text = text.replace(
            '"$actual_path/bin/switch-to-configuration"', f'"{temp}/activate"'
        )
        text = text.replace(
            '"$previous/bin/switch-to-configuration"', f'"{temp}/activate"'
        )
        if name == "switch":
            # Exercise HTTP readiness even though Partridge has no endpoints.
            text = text.replace(
                "http_checks=()", "http_checks=(http://127.0.0.1:9465/api/items)"
            )
            text = re.sub(r"/nix/store/[^/]+/bin/curl", str(temp / "curl"), text)
            text = text.replace(f'"{temp}/activate"', f'"{temp}/restore"')
            text = text.replace('"$previous/sw/bin/nix-env"', f'"{temp}/nix-env"')
            text = text.replace('"$previous/sw/bin/systemctl"', f'"{temp}/systemctl"')
            text = text.replace(
                "/run/lab-switch-recovery.XXXXXX", str(temp / "recovery.XXXXXX")
            )
        text = text.replace('"$EUID" != 0', "0 != 0")
        text = text.replace("/run/lock/lab-bootstrap.lock", str(temp / "lock"))
        text = text.replace("sleep 5", ":")
        scripts[name] = temp / name
        scripts[name].write_text(text)
        subprocess.run(["bash", "-n", str(scripts[name])], check=True)

    def run(name, args=(), request="", **overrides):
        log.write_text("")
        env = dict(
            os.environ,
            PATH=f"{temp}:{os.environ['PATH']}",
            TEST_LOG=str(log),
            TEST_PATH=expected,
            TEST_PREVIOUS=previous,
            SSH_ORIGINAL_COMMAND=request,
        )
        env.update(overrides)
        result = subprocess.run(
            ["bash", str(scripts[name]), *args], env=env, text=True, capture_output=True
        )
        assert not list(temp.glob("recovery.*")), "recovery root leaked"
        return result, log.read_text()

    pinned = f"lab-switch {sha} {cache} {key} {expected}"
    result, calls = run("switch", request=pinned)
    assert result.returncode == 0, result.stderr
    assert "--option max-jobs 0" in calls and "--option builders " in calls
    assert "--option require-sigs true" in calls
    assert f"nix-store --realise {expected}" in calls and "nix build" not in calls
    assert expected not in calls.splitlines()[0]  # evaluated flake, then path check
    assert "nixos-rebuild switch --flake github:EdwardSalkeld/lab/" in calls
    assert f"--realise {previous} --option builders  --option max-jobs 0" in calls
    assert calls.index("--add-root") < calls.index("nixos-rebuild switch")
    assert "restore switch" not in calls and "nix-env" not in calls
    assert (
        "curl --fail --silent --show-error --max-time 10 --output /dev/null http://127.0.0.1:9465/api/items"
        in calls
    )
    for request in (
        "",
        "lab-switch bad test key path",
        pinned + " extra",
        f"lab-switch {sha} other {key} {expected}",
        f"lab-switch {sha} {cache} test.cachix.org-1:AAAA= {expected}",
    ):
        result, calls = run("switch", request=request)
        assert result.returncode != 0 and not calls, (request, calls)
    for overrides in ({"TEST_FETCH_FAIL": "1"}, {"TEST_PATH": previous}):
        result, calls = run("switch", request=pinned, **overrides)
        assert result.returncode != 0 and "nixos-rebuild" not in calls
    result, calls = run("switch", request="lab-switch")
    assert result.returncode == 0 and "nix build" not in calls
    assert "--refresh" in calls
    for overrides in ({"TEST_PIN_FAIL": "1"}, {"TEST_READLINK_FAIL": "1"}):
        result, calls = run("switch", request=pinned, **overrides)
        assert result.returncode != 0 and "nixos-rebuild" not in calls

    restore_profile = f"nix-env --profile /nix/var/nix/profiles/system --set {previous}"
    for overrides in (
        {"TEST_SWITCH_FAIL": "1"},
        {"TEST_HEALTH_FAIL": "1"},
        {"TEST_HTTP_FAIL": "1"},
        {"TEST_HEALTH_UNTIL_RECOVERY": "1"},
        {"TEST_SWITCH_FAIL": "1", "TEST_HEALTH_FAIL": "1"},
        # Re-deploying the same closure must not select an older generation.
        {"TEST_SWITCH_FAIL": "1", "TEST_PREVIOUS": expected},
    ):
        result, calls = run("switch", request=pinned, **overrides)
        prior = overrides.get("TEST_PREVIOUS", previous)
        profile = f"nix-env --profile /nix/var/nix/profiles/system --set {prior}"
        assert result.returncode != 0, result.stderr
        assert calls.count(profile) == 1 and calls.count("restore switch") == 1
        assert calls.index(profile) < calls.index("restore switch")
        assert "--rollback" not in calls and calls.count("nixos-rebuild") == 1
        if "TEST_HEALTH_FAIL" not in overrides and "TEST_HTTP_FAIL" not in overrides:
            assert "systemctl start " not in calls
        if "TEST_HTTP_FAIL" in overrides:
            assert "systemctl start " in calls
            assert "health checks still failing after service recovery" in result.stderr
    for overrides, diagnostic in (
        ({"TEST_RECOVERY_FAIL": "1"}, "activating the previous system also failed"),
        ({"TEST_PROFILE_FAIL": "1"}, "restoring the previous system profile failed"),
    ):
        result, calls = run(
            "switch",
            request=pinned,
            TEST_SWITCH_FAIL="1",
            TEST_HEALTH_FAIL="1",
            **overrides,
        )
        assert result.returncode != 0 and diagnostic in result.stderr
        assert restore_profile in calls and calls.count("restore switch") == 1
        assert "systemctl start " in calls, "last-resort service recovery was skipped"

    args = ["partridge", sha, cache, key, expected]
    result, calls = run("bootstrap", ["switch", *args, previous], TEST_LOCK_FAIL="1")
    assert result.returncode != 0 and "nix-env" not in calls
    result, calls = run("bootstrap", ["plan", *args])
    assert result.returncode == 0, result.stderr
    assert "nix store diff-closures" in calls
    assert f"nix-store --realise {expected}" in calls and "nix build" not in calls
    assert "nix-env" not in calls and "activate" not in calls
    for overrides in ({"TEST_FETCH_FAIL": "1"}, {"TEST_PATH": previous}):
        result, calls = run("bootstrap", ["switch", *args, previous], **overrides)
        assert result.returncode != 0 and "nix-env" not in calls
    result, calls = run("bootstrap", ["switch", *args, expected])
    assert result.returncode != 0 and "nix-env" not in calls
    result, calls = run("bootstrap", ["switch", *args, previous])
    assert result.returncode == 0, result.stderr
    assert f"nix-env --profile /nix/var/nix/profiles/system --set {expected}" in calls
    assert "nixos-rebuild" not in calls
    result, calls = run("bootstrap", ["switch", *args, previous], TEST_SWITCH_FAIL="1")
    assert result.returncode != 0
    assert f"nix-env --profile /nix/var/nix/profiles/system --set {previous}" in calls

print("CI deployment fetch, refusal, legacy compatibility and recovery checks passed")
