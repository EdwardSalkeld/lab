#!/usr/bin/env bash
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Run as root' >&2; exit 1; }
host=$(hostname -s)
[[ $host == sol || $host == luna ]] || { echo 'Only sol and luna are supported' >&2; exit 1; }
[[ $(uname -m) == x86_64 ]] || { echo 'Expected x86_64' >&2; exit 1; }
dir=$(cd -- "$(dirname -- "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fL --retry 3 -o "$tmp/alloy.zip" https://github.com/grafana/alloy/releases/download/v1.16.0/alloy-linux-amd64.zip
echo "eb5596594498c32e8e400694e9acb4a9176fe524cdbc3d9ccbe5b0afe5a02f9c  $tmp/alloy.zip" | sha256sum -c -
python3 -m zipfile -e "$tmp/alloy.zip" "$tmp"
chmod 755 "$tmp/alloy-linux-amd64"
HOSTNAME="$host" "$tmp/alloy-linux-amd64" validate "$dir/config.alloy"
install -d -m 755 /usr/local/lib/proxmox-journal-alloy /etc/proxmox-journal-alloy
install -m 755 "$tmp/alloy-linux-amd64" /usr/local/lib/proxmox-journal-alloy/alloy
install -m 644 "$dir/config.alloy" /etc/proxmox-journal-alloy/config.alloy
printf 'HOSTNAME=%s\n' "$host" > /etc/default/proxmox-journal-alloy
install -m 644 "$dir/proxmox-journal-alloy.service" /etc/systemd/system/proxmox-journal-alloy.service
systemctl daemon-reload
systemctl enable proxmox-journal-alloy.service
systemctl restart proxmox-journal-alloy.service
systemctl is-active --quiet proxmox-journal-alloy.service
