#!/usr/bin/env bash
# Run as root on the named host. Fetch/review first; switch is a separate step.
set -euo pipefail

if [[ $# -lt 6 || $# -gt 7 ]]; then
  echo 'usage: bootstrap-ci-deploy.sh <plan|switch> <host> <sha> <cache-name> <cache-key> <system-path> [reviewed-current-system]' >&2
  exit 2
fi
mode=$1 host=$2 sha=$3 cache_name=$4 cache_key=$5 expected_path=$6
reviewed_current=${7:-}
if [[ "$mode" != plan && "$mode" != switch ]] ||
   [[ "$host" != "$(hostname -s)" || ! "$sha" =~ ^[0-9a-f]{40}$ ||
      ! "$cache_name" =~ ^[a-z0-9][a-z0-9-]*$ ||
      ! "$cache_key" =~ ^[a-z0-9.-]+-1:[A-Za-z0-9+/=]+$ ||
      ! "$expected_path" =~ ^/nix/store/[a-z0-9]{32}-[A-Za-z0-9.+_-]+$ ]]; then
  echo 'invalid bootstrap request or wrong host' >&2
  exit 2
fi
if [[ "$EUID" != 0 ]]; then
  echo 'run this script as root' >&2
  exit 2
fi

exec 9>/run/lock/lab-bootstrap.lock
flock -n 9 || { echo 'another bootstrap is running' >&2; exit 1; }
nix=/run/current-system/sw/bin/nix
nix_env=/run/current-system/sw/bin/nix-env
systemctl=/run/current-system/sw/bin/systemctl
source="github:EdwardSalkeld/lab/${sha}"
options=(--option extra-substituters "https://${cache_name}.cachix.org"
         --option extra-trusted-public-keys "$cache_key"
         --option require-sigs true --option builders "" --option max-jobs 0)

# This fetches the complete closure or fails. No local or remote builders.
actual_path="$("$nix" build --no-link --print-out-paths "${options[@]}" \
  "${source}#nixosConfigurations.${host}.config.system.build.toplevel")"
if [[ "$actual_path" != "$expected_path" ]]; then
  echo "CI path mismatch: expected $expected_path; got $actual_path" >&2
  exit 1
fi
previous=$(readlink -f /run/current-system)
printf 'Current: %s\nPrepared: %s\n' "$previous" "$actual_path"
"$nix" store diff-closures "$previous" "$actual_path"
if [[ "$mode" == plan ]]; then
  echo 'Closure fetched and compared; no profile or service changes.'
  exit 0
fi
if [[ "$reviewed_current" != "$previous" ]]; then
  echo 'current system differs from the reviewed plan; rerun plan before switching' >&2
  exit 1
fi
units="$("$nix" eval --raw "${options[@]}" \
  "${source}#nixosConfigurations.${host}.config.alcachofa.remoteDeploy.postSwitchHealthchecks" \
  --apply 'units: builtins.concatStringsSep "\n" units')"
healthchecks=()
if [[ -n "$units" ]]; then
  mapfile -t healthchecks <<< "$units"
fi
healthy() {
  local unit
  for unit in "${healthchecks[@]}"; do
    "$systemctl" is-active --quiet "$unit" || return 1
  done
}
healthy || { echo 'existing health checks fail; fix them before bootstrapping' >&2; exit 1; }

# Activate the exact fetched closure; do not invoke a rebuilding switch.
recover() {
  trap - EXIT HUP INT TERM
  echo 'bootstrap failed; restoring the previous system' >&2
  "$nix_env" --profile /nix/var/nix/profiles/system --set "$previous" || true
  "$previous/bin/switch-to-configuration" switch || true
  local unit
  for unit in "${healthchecks[@]}"; do
    "$systemctl" start "$unit" || true
  done
  exit 1
}
trap recover EXIT
trap 'exit 1' HUP INT TERM
"$nix_env" --profile /nix/var/nix/profiles/system --set "$actual_path"
"$actual_path/bin/switch-to-configuration" switch
sleep 5
healthy
trap - EXIT HUP INT TERM
echo 'bootstrap switch and health checks passed'
