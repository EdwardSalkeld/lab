#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
secret_file="${1:-$repo_root/nixos/hosts/partridge/secrets/bitwarden-mirror.yaml}"
work_dir="$(mktemp -d)"
state_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$work_dir" "$state_dir"
}
trap cleanup EXIT

json="$(sops -d --output-type json "$secret_file")"

export SOURCE_BW_CLIENTID
SOURCE_BW_CLIENTID="$(jq -r '.source_bw_clientid' <<<"$json")"
export SOURCE_BW_CLIENTSECRET
SOURCE_BW_CLIENTSECRET="$(jq -r '.source_bw_clientsecret' <<<"$json")"
export SOURCE_BW_MASTER_PASSWORD
SOURCE_BW_MASTER_PASSWORD="$(jq -r '.source_bw_master_password' <<<"$json")"
export DEST_BW_CLIENTID
DEST_BW_CLIENTID="$(jq -r '.dest_bw_clientid' <<<"$json")"
export DEST_BW_CLIENTSECRET
DEST_BW_CLIENTSECRET="$(jq -r '.dest_bw_clientsecret' <<<"$json")"
export DEST_BW_MASTER_PASSWORD
DEST_BW_MASTER_PASSWORD="$(jq -r '.dest_bw_master_password' <<<"$json")"

cd "$repo_root/tools/bitwarden-mirror"
go run ./cmd/bitwarden-mirror \
  --dry-run \
  --work-dir "$work_dir" \
  --state-dir "$state_dir"
