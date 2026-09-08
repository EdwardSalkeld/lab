#!/usr/bin/env bash
# Run on the orchestrator (fourth) by /opt/deploy/run.sh.
# Applies the lab terraform (Proxmox VMs) against the Terraform Cloud backend.
# Auth: TF_TOKEN_app_terraform_io comes from /var/lib/deploy/creds/lab.env.
# Safety: protected VMs are rejected if a plan would create, delete, or replace
# them, rather than auto-applying a potentially destructive plan.
set -euo pipefail

: "${TF_TOKEN_app_terraform_io:?TFC token missing — set it in creds/lab.env}"

exec 8>"../lab-terraform.lock"
flock -w 1800 8

terraform -chdir=terraform init -input=false

plan_file="$(mktemp)"
plan_json="$(mktemp)"
trap 'rm -f "$plan_file" "$plan_json"' EXIT

# The Proxmox provider has previously turned a Luna authorization failure
# during refresh into a missing Kite VM. Apply an exact, non-refreshing plan
# so that failure cannot discard state and turn into a replacement create.
terraform -chdir=terraform plan -input=false -refresh=false -out="$plan_file"
terraform -chdir=terraform show -json "$plan_file" >"$plan_json"
bash deploy/assert-safe-terraform-plan.sh "$plan_json"
terraform -chdir=terraform apply -input=false "$plan_file"
