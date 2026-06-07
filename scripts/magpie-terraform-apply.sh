#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
image_dir="$repo_root/.terraform-images"
image_path="$image_dir/magpie.qcow2"

mkdir -p "$image_dir"

nix build "$repo_root#packages.x86_64-linux.magpie-image" --out-link "$image_dir/magpie-result"
cp -f "$image_dir/magpie-result"/*.qcow2 "$image_path"
chmod 0644 "$image_path"

export TF_VAR_magpie_image_path="$image_path"

set -a
source "$repo_root/terraform/.env"
set +a

nix shell nixpkgs#terraform -c terraform -chdir="$repo_root/terraform" apply "$@"
