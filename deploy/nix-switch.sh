#!/usr/bin/env bash
# Run on the orchestrator (fourth) by /opt/deploy/run.sh.
# SSHes each NixOS host as root; the forced command on the host's key runs the
# pinned, cache-only switch. One failing host does not stop the others.
set -euo pipefail

usage() {
  echo 'usage: nix-switch <sha> <cache-name> <cache-public-key> <host>=<system-path>...' >&2
  exit 2
}

# Every target is fully qualified so the loop has no host-specific addressing
# logic. Falcon's Tailnet address is published through our managed DNS.
# This fixed list, not the request, decides which hosts fourth will touch.
# scripts/check-host-lists.py keeps it equal to the flake's hosts.
HOSTS=(
  falcon.ts.alcachofa.faith
  kite.int.alcachofa.faith
  magpie.int.alcachofa.faith
  partridge.int.alcachofa.faith
)

read -r -a args <<<"${SSH_ORIGINAL_COMMAND:-}"
job="${args[0]:-}"
sha="${args[1]:-}"
cache_name="${args[2]:-}"
cache_key="${args[3]:-}"
if [[ "$job" != nix-switch || ! "$sha" =~ ^[0-9a-f]{40}$ ||
      ! "$cache_name" =~ ^[a-z0-9][a-z0-9-]*$ ||
      ! "$cache_key" =~ ^[a-z0-9.-]+-1:[A-Za-z0-9+/=]+$ ]]; then
  usage
fi

declare -A PATHS=()
for pair in "${args[@]:4}"; do
  if [[ ! "$pair" =~ ^([a-z][a-z0-9-]*)=(/nix/store/[a-z0-9]{32}-[A-Za-z0-9.+_-]+)$ ]]; then
    echo "invalid host system: $pair" >&2
    exit 2
  fi
  host="${BASH_REMATCH[1]}"
  known=false
  for h in "${HOSTS[@]}"; do
    [[ "${h%%.*}" == "$host" ]] && known=true
  done
  if [[ "$known" != true || -v "PATHS[$host]" ]]; then
    echo "unknown or repeated host: $host" >&2
    exit 2
  fi
  PATHS[$host]="${BASH_REMATCH[2]}"
done
for h in "${HOSTS[@]}"; do
  if [[ ! -v "PATHS[${h%%.*}]" ]]; then
    echo "missing system path for ${h%%.*}" >&2
    usage
  fi
done

if ! git merge-base --is-ancestor "$sha" HEAD; then
  echo "refusing to deploy a commit outside current main: $sha" >&2
  exit 2
fi

KEY="${ONWARD_SSH_KEY:?dispatcher must set ONWARD_SSH_KEY}"

rc=0
for h in "${HOSTS[@]}"; do
  echo "==> switch ${h} to ${sha}"
  if ssh -i "${KEY}" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
       "root@${h}" lab-switch "$sha" "$cache_name" "$cache_key" "${PATHS[${h%%.*}]}"; then
    echo "    ${h} ok"
  else
    echo "    ${h} FAILED" >&2
    rc=1
  fi
done
exit "${rc}"
