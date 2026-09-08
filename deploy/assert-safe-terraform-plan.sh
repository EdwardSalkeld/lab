#!/usr/bin/env bash
# Reject Terraform plans that would replace an existing protected VM.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $(basename "$0") PLAN_JSON" >&2
  exit 2
fi

unsafe_changes="$(jq -r '
    .resource_changes[]?
    | select(
        .address == "proxmox_virtual_environment_vm.kite[0]"
        or .address == "proxmox_virtual_environment_vm.magpie"
        or .address == "proxmox_virtual_environment_vm.partridge"
      )
    | select(any(.change.actions[]; . == "create" or . == "delete"))
    | "\(.address): \(.change.actions | join(","))"
  ' "$1")"

if [[ -n "$unsafe_changes" ]]; then
  echo "refusing Terraform plan that creates, deletes, or replaces a protected VM:" >&2
  printf '%s\n' "$unsafe_changes" >&2
  exit 1
fi
