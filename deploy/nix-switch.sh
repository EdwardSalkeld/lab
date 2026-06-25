#!/usr/bin/env bash
# Run on the orchestrator (fourth) by /opt/deploy/run.sh.
# SSHes each NixOS host as root; the forced command on the host's key runs the
# actual `nixos-rebuild switch` (build-on-target), so the command sent here is
# descriptive only. One failing host does not stop the others.
set -euo pipefail

HOSTS=(partridge magpie)
KEY="${ONWARD_SSH_KEY:?dispatcher must set ONWARD_SSH_KEY}"

rc=0
for h in "${HOSTS[@]}"; do
  echo "==> nixos-rebuild on ${h}"
  if ssh -i "${KEY}" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
       "root@${h}.int.alcachofa.faith" lab-switch; then
    echo "    ${h} ok"
  else
    echo "    ${h} FAILED" >&2
    rc=1
  fi
done
exit "${rc}"
