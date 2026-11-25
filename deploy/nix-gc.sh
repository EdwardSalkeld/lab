#!/usr/bin/env bash
# Run on the orchestrator (fourth) by the host-specific nix-gc-<host>.sh
# wrappers, one per host in HOSTS.
set -euo pipefail

host="${1:?usage: nix-gc.sh <host>}"
key="${ONWARD_SSH_KEY:?dispatcher must set ONWARD_SSH_KEY}"

# Same fixed list and addressing as nix-switch.sh;
# scripts/check-host-lists.py keeps both equal to the flake's hosts.
HOSTS=(
  falcon.ts.alcachofa.faith
  kite.int.alcachofa.faith
  magpie.int.alcachofa.faith
  partridge.int.alcachofa.faith
)

target=
for h in "${HOSTS[@]}"; do
  [[ "${h%%.*}" == "$host" ]] && target="$h"
done
if [[ -z "$target" ]]; then
  echo "unsupported host: $host" >&2
  exit 2
fi

echo "==> Nix GC on $host"
ssh -i "$key" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
  "root@$target" nix-gc
