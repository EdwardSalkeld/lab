#!/usr/bin/env bash
# Run on the orchestrator (fourth) by /opt/deploy/run.sh.
# SSHes each NixOS host as root; the forced command on the host's key runs the
# pinned, cache-only switch. One failing host does not stop the others.
set -euo pipefail

read -r job sha cache_name cache_key falcon_path kite_path magpie_path partridge_path extra <<<"${SSH_ORIGINAL_COMMAND:-}"
if [[ "$job" != nix-switch || ! "$sha" =~ ^[0-9a-f]{40}$ ||
      ! "$cache_name" =~ ^[a-z0-9][a-z0-9-]*$ ||
      ! "$cache_key" =~ ^[a-z0-9.-]+-1:[A-Za-z0-9+/=]+$ || -n "${extra:-}" ]]; then
  echo 'usage: nix-switch <sha> <cache-name> <cache-public-key> <four system paths>' >&2
  exit 2
fi
for path in "$falcon_path" "$kite_path" "$magpie_path" "$partridge_path"; do
  if [[ ! "$path" =~ ^/nix/store/[a-z0-9]{32}-[A-Za-z0-9.+_-]+$ ]]; then
    echo "invalid system path: $path" >&2
    exit 2
  fi
done
if ! git merge-base --is-ancestor "$sha" HEAD; then
  echo "refusing to deploy a commit outside current main: $sha" >&2
  exit 2
fi

# Every target is fully qualified so the loop has no host-specific addressing
# logic. Falcon's Tailnet address is published through our managed DNS.
HOSTS=(
  falcon.ts.alcachofa.faith
  kite.int.alcachofa.faith
  magpie.int.alcachofa.faith
  partridge.int.alcachofa.faith
)
PATHS=("$falcon_path" "$kite_path" "$magpie_path" "$partridge_path")
KEY="${ONWARD_SSH_KEY:?dispatcher must set ONWARD_SSH_KEY}"

rc=0
for i in "${!HOSTS[@]}"; do
  h="${HOSTS[$i]}"
  echo "==> switch ${h} to ${sha}"
  if ssh -i "${KEY}" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
       "root@${h}" lab-switch "$sha" "$cache_name" "$cache_key" "${PATHS[$i]}"; then
    echo "    ${h} ok"
  else
    echo "    ${h} FAILED" >&2
    rc=1
  fi
done
exit "${rc}"
