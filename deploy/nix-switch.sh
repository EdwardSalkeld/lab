#!/usr/bin/env bash
# Run on the orchestrator (fourth) by /opt/deploy/run.sh.
# SSHes each NixOS host as root; the forced command on the host's key runs the
# actual `nixos-rebuild switch` (build-on-target), so the command sent here is
# descriptive only. One failing host does not stop the others.
set -euo pipefail

# Falcon is outside the LAN, so use its stable MagicDNS name rather than the
# LAN-only internal zone used by the Proxmox VMs.
HOSTS=(partridge magpie kite falcon.tailb35748.ts.net)
KEY="${ONWARD_SSH_KEY:?dispatcher must set ONWARD_SSH_KEY}"

rc=0
for h in "${HOSTS[@]}"; do
  if [ "${h}" = "falcon.tailb35748.ts.net" ]; then
    target="${h}"
    label="falcon"
  else
    target="${h}.int.alcachofa.faith"
    label="${h}"
  fi
  echo "==> nixos-rebuild on ${label}"
  if ssh -i "${KEY}" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
       "root@${target}" lab-switch; then
    echo "    ${label} ok"
  else
    echo "    ${label} FAILED" >&2
    rc=1
  fi
done
exit "${rc}"
