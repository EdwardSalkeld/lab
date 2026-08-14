#!/usr/bin/env bash
# Run on the orchestrator (fourth) by the host-specific wrappers below.
set -euo pipefail

host="${1:?usage: nix-gc.sh <host>}"
key="${ONWARD_SSH_KEY:?dispatcher must set ONWARD_SSH_KEY}"

case "$host" in
  magpie | partridge) ;;
  *)
    echo "unsupported host: $host" >&2
    exit 2
    ;;
esac

echo "==> Nix GC on $host"
ssh -i "$key" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
  "root@$host.int.alcachofa.faith" nix-gc
