#!/usr/bin/env bash
# Run on the orchestrator (fourth) by /opt/deploy/run.sh.
# The dispatcher starts from origin/main, so this script fetches the requested
# PR ref into a temporary worktree and plans from that checked-out source.
set -euo pipefail

: "${TF_TOKEN_app_terraform_io:?TFC token missing - set it in creds/lab.env}"

read -r job pr_number head_sha _ <<<"${SSH_ORIGINAL_COMMAND:-}"

if [[ "$job" != "plan-terraform" ]]; then
  echo "unexpected job: $job" >&2
  exit 2
fi

if [[ ! "$pr_number" =~ ^[0-9]+$ ]]; then
  echo "usage: plan-terraform <pull-request-number> <head-sha>" >&2
  exit 2
fi

if [[ ! "$head_sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "usage: plan-terraform <pull-request-number> <head-sha>" >&2
  exit 2
fi

exec 8>"../lab-terraform.lock"
flock -w 1800 8

git fetch --quiet origin "pull/${pr_number}/head"
actual_sha="$(git rev-parse FETCH_HEAD)"
if [[ "$actual_sha" != "$head_sha" ]]; then
  echo "PR head SHA mismatch: expected $head_sha, got $actual_sha" >&2
  exit 1
fi

plan_dir="$(mktemp -d "../lab-pr-${pr_number}-terraform-plan.XXXXXXXX")"
trap 'rm -rf "$plan_dir"' EXIT

git archive "$head_sha" | tar -x -C "$plan_dir"

cd "$plan_dir"
terraform -chdir=terraform init -input=false

set +e
terraform -chdir=terraform plan -input=false -no-color -detailed-exitcode
rc=$?
set -e

case "$rc" in
  0)
    echo "Terraform plan completed: no changes."
    ;;
  2)
    echo "Terraform plan completed: changes present."
    exit 0
    ;;
  *)
    exit "$rc"
    ;;
esac
