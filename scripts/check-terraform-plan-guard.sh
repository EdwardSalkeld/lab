#!/usr/bin/env bash
# Check deploy/assert-safe-terraform-plan.sh against fixture plans, and that it
# protects every Proxmox VM declared in terraform/.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
guard="$repo_root/deploy/assert-safe-terraform-plan.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

plan() {
  local address="$1" actions="$2"
  jq -n --arg address "$address" --argjson actions "$actions" '{
    format_version: "1.2",
    resource_changes: [
      {
        address: "proxmox_virtual_environment_download_file.nixos_minimal_iso",
        change: { actions: ["delete", "create"] }
      },
      { address: $address, change: { actions: $actions } }
    ]
  }' > "$work/plan.json"
}

expect() {
  local want="$1" address="$2" actions="$3" rc=0
  plan "$address" "$actions"
  "$guard" "$work/plan.json" > /dev/null 2>&1 || rc=$?
  if [[ "$rc" -ne "$want" ]]; then
    fail "$address $actions exited $rc, expected $want"
  fi
}

# Every VM resource, with [0] for the ones that use count, as plan JSON
# addresses them.
mapfile -t addresses < <(
  awk '
    /^resource "proxmox_virtual_environment_vm" "/ {
      split($0, parts, "\"")
      address = "proxmox_virtual_environment_vm." parts[4]
      counted = 0
      next
    }
    address != "" && /^  (count|for_each) *=/ { counted = 1 }
    address != "" && /^}/ {
      print address (counted ? "[0]" : "")
      address = ""
    }
  ' "$repo_root"/terraform/*.tf | sort
)

if [[ "${#addresses[@]}" -eq 0 ]]; then
  fail "found no proxmox_virtual_environment_vm resources in terraform/"
fi

for address in "${addresses[@]}"; do
  if ! grep -qF "\"$address\"" "$guard"; then
    fail "$address is not protected by $(basename "$guard")"
  fi

  expect 1 "$address" '["delete","create"]'
  expect 1 "$address" '["create","delete"]'
  expect 1 "$address" '["create"]'
  expect 1 "$address" '["delete"]'
  expect 0 "$address" '["update"]'
  expect 0 "$address" '["no-op"]'
  expect 0 "$address" '["read"]'
done

# Resources the guard does not protect may still be replaced.
expect 0 proxmox_virtual_environment_file.example '["delete","create"]'

echo '{"format_version":"1.2"}' > "$work/plan.json"
"$guard" "$work/plan.json" > /dev/null 2>&1 || fail "plan with no resource_changes was refused"

if [[ "$failures" -ne 0 ]]; then
  echo "$failures check(s) failed" >&2
  exit 1
fi

echo "PASS: plan guard refuses create/delete on ${addresses[*]}"
