#!/usr/bin/env bash
# Run on the orchestrator (fourth) by /opt/deploy/run.sh.
# Applies the lab terraform (Proxmox VMs) against the Terraform Cloud backend.
# Auth: TF_TOKEN_app_terraform_io comes from /var/lib/deploy/creds/lab.env.
# Safety: stateful resources carry lifecycle.prevent_destroy, so a plan that
# would destroy/replace one errors here rather than auto-applying.
set -euo pipefail

: "${TF_TOKEN_app_terraform_io:?TFC token missing — set it in creds/lab.env}"

terraform -chdir=terraform init -input=false
terraform -chdir=terraform apply -input=false -auto-approve
