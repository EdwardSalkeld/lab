#!/usr/bin/env bash
# Run on the orchestrator (fourth) by /opt/deploy/run.sh.
# Applies the lab terraform (Proxmox VMs) against the Terraform Cloud backend.
# Auth: TF_TOKEN_app_terraform_io comes from /var/lib/deploy/creds/lab.env.
# Safety: stateful resources carry lifecycle.prevent_destroy, so a plan that
# would destroy/replace one errors here rather than auto-applying.
set -euo pipefail

: "${TF_TOKEN_app_terraform_io:?TFC token missing — set it in creds/lab.env}"

hello_vm_files_changed() {
  git rev-parse --verify HEAD^ >/dev/null 2>&1 || return 1
  git diff --name-only HEAD^ HEAD -- \
    terraform/hello-vm.tf \
    terraform/variables.tf \
    terraform/outputs.tf | grep -q .
}

stop_wren_if_needed() {
  hello_vm_files_changed || return 0

  vm_id="$(terraform -chdir=terraform state show proxmox_virtual_environment_vm.hello 2>/dev/null | sed -n 's/^vm_id *= *//p' | head -n1)"
  [ -n "${vm_id}" ] || return 0

  proxmox_endpoint="${PROXMOXENDPOINT:-${TF_VAR_PROXMOXENDPOINT:-}}"
  proxmox_token="${PROXMOXTOKEN:-${TF_VAR_PROXMOXTOKEN:-}}"
  [ -n "${proxmox_endpoint}" ] || {
    printf 'wren pre-stop requested but PROXMOXENDPOINT/TF_VAR_PROXMOXENDPOINT is unset\n' >&2
    exit 1
  }
  [ -n "${proxmox_token}" ] || {
    printf 'wren pre-stop requested but PROXMOXTOKEN/TF_VAR_PROXMOXTOKEN is unset\n' >&2
    exit 1
  }

  api_base="${proxmox_endpoint%/}/api2/json/nodes/sol/qemu/${vm_id}/status"
  auth_header="Authorization: PVEAPIToken=${proxmox_token}"
  current_status="$(
    curl -fsSL -H "${auth_header}" "${api_base}/current" | \
      python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["status"])'
  )"

  if [ "${current_status}" = "stopped" ]; then
    printf 'wren (%s) already stopped before terraform apply\n' "${vm_id}"
    return 0
  fi

  printf 'stopping wren (%s) before terraform apply so cloud-init updates do not hotplug ide2\n' "${vm_id}"
  curl -fsSL -X POST -H "${auth_header}" "${api_base}/stop" >/dev/null

  for _ in $(seq 1 30); do
    current_status="$(
      curl -fsSL -H "${auth_header}" "${api_base}/current" | \
        python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["status"])'
    )"
    [ "${current_status}" = "stopped" ] && return 0
    sleep 2
  done

  printf 'timed out waiting for wren (%s) to stop; last status: %s\n' "${vm_id}" "${current_status}" >&2
  exit 1
}

terraform -chdir=terraform init -input=false
stop_wren_if_needed
terraform -chdir=terraform apply -input=false -auto-approve
