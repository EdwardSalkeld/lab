#!/usr/bin/env python3
"""Exercise deployment refusal and recovery paths without changing a host."""
import json
import os
from pathlib import Path
import subprocess
import tempfile


def output(*args):
    return subprocess.check_output(args, text=True).strip()


root = Path(__file__).resolve().parents[1]
context = json.loads(output(
    "nix", "eval", "--json",
    f"{root}#nixosConfigurations.partridge.config.users.users.root.openssh.authorizedKeys.keys",
    "--apply", "keys: builtins.getContext (builtins.head keys)",
))
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
key = "test.cachix.org-1:AAAA="

with tempfile.TemporaryDirectory(prefix="check-ci-deploy-") as directory:
    temp = Path(directory)
    log = temp / "calls"
    stub = temp / "stub"
    stub.write_text('''#!/usr/bin/env bash
name=${0##*/}
printf '%s' "$name" >> "$TEST_LOG"
printf ' %s' "$@" >> "$TEST_LOG"
printf '\\n' >> "$TEST_LOG"
case "$name" in
  nix)
    if [[ "$1" == build ]]; then
      [[ "${TEST_FETCH_FAIL:-0}" == 0 ]] || exit 1
      printf '%s\\n' "$TEST_PATH"
    fi
    ;;
  nixos-rebuild)
    [[ "${TEST_SWITCH_FAIL:-0}" == 0 || "$*" == *--rollback* ]] || exit 1
    ;;
  activate) [[ "${TEST_SWITCH_FAIL:-0}" == 0 ]] || exit 1 ;;
  hostname) echo partridge ;;
  readlink) echo "$TEST_PREVIOUS" ;;
esac
''')
    stub.chmod(0o755)
    for name in ("nix", "nix-env", "nixos-rebuild", "systemctl", "activate", "hostname", "readlink"):
        (temp / name).symlink_to(stub)
    scripts = {}
    for name, text in (("switch", switch), ("bootstrap", bootstrap)):
        text = text.replace("/run/current-system/sw/bin/", f"{temp}/")
        text = text.replace('"$actual_path/bin/switch-to-configuration"', f'"{temp}/activate"')
        text = text.replace('"$previous/bin/switch-to-configuration"', f'"{temp}/activate"')
        text = text.replace('"$EUID" != 0', '0 != 0')
        text = text.replace("/run/lock/lab-bootstrap.lock", str(temp / "lock"))
        text = text.replace("sleep 5", ":")
        scripts[name] = temp / name
        scripts[name].write_text(text)
        subprocess.run(["bash", "-n", str(scripts[name])], check=True)

    def run(name, args=(), request="", **overrides):
        log.write_text("")
        env = dict(os.environ, PATH=f"{temp}:{os.environ['PATH']}",
                   TEST_LOG=str(log), TEST_PATH=expected, TEST_PREVIOUS=previous,
                   SSH_ORIGINAL_COMMAND=request)
        env.update(overrides)
        result = subprocess.run(["bash", str(scripts[name]), *args], env=env,
                                text=True, capture_output=True)
        return result, log.read_text()

    pinned = f"lab-switch {sha} test {key} {expected}"
    result, calls = run("switch", request=pinned)
    assert result.returncode == 0, result.stderr
    assert "--option max-jobs 0" in calls and '--option builders ' in calls
    assert "--option require-sigs true" in calls
    assert expected not in calls.splitlines()[0]  # evaluated flake, then path check
    assert "nixos-rebuild switch --flake github:EdwardSalkeld/lab/" in calls
    for request in ("", "lab-switch bad test key path", pinned + " extra"):
        result, calls = run("switch", request=request)
        assert result.returncode != 0 and not calls, (request, calls)
    for overrides in ({"TEST_FETCH_FAIL": "1"}, {"TEST_PATH": previous}):
        result, calls = run("switch", request=pinned, **overrides)
        assert result.returncode != 0 and "nixos-rebuild" not in calls
    result, calls = run("switch", request="lab-switch")
    assert result.returncode == 0 and "nix build" not in calls
    assert "--refresh" in calls
    result, calls = run("switch", request=pinned, TEST_SWITCH_FAIL="1")
    assert result.returncode != 0 and "--rollback" in calls

    args = ["partridge", sha, "test", key, expected]
    result, calls = run("bootstrap", ["plan", *args])
    assert result.returncode == 0, result.stderr
    assert "nix store diff-closures" in calls
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
