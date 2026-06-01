#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
mode="--dry-run"
secret_file="$repo_root/nixos/hosts/partridge/secrets/bitwarden-mirror.yaml"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply)
      mode=""
      shift
      ;;
    --dry-run)
      mode="--dry-run"
      shift
      ;;
    *)
      secret_file="$1"
      shift
      ;;
  esac
done

work_dir="$(mktemp -d)"
state_dir="$repo_root/.bitwarden-mirror-state"
mkdir -p "$state_dir"

cleanup() {
  rm -rf "$work_dir"
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
  ${mode:+"$mode"} \
  --work-dir "$work_dir" \
  --state-dir "$state_dir"
