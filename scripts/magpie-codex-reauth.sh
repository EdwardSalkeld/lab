#!/usr/bin/env bash
set -euo pipefail

host=edward@magpie

echo 'Recent magpie worker failures:'
ssh -n -o BatchMode=yes "$host" \
  "sudo -n journalctl -u chatting-worker --since '1 hour ago' --no-pager | rg 'worker_processed.*(execution_error|dead_letter)|401 Unauthorized|invalidated oauth token' | tail -20 || true"

echo
echo 'Follow the device login instructions below in your browser.'
ssh -tt -o BatchMode=yes "$host" \
  'sudo -n -u worker env HOME=/var/lib/worker CODEX_HOME=/var/lib/worker/.codex /etc/profiles/per-user/edward/bin/codex login --device-auth'

echo
echo 'Checking the new login with a read-only Codex request:'
ssh -n -o BatchMode=yes "$host" \
  "sudo -n -u worker env HOME=/var/lib/worker CODEX_HOME=/var/lib/worker/.codex /etc/profiles/per-user/edward/bin/codex exec --cd /var/lib/worker --skip-git-repo-check --sandbox read-only 'Reply with exactly OK.' </dev/null"

echo
echo 'Codex is working as worker. Resend any requests that failed before login.'
