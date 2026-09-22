#!/usr/bin/env bash
# Install reviewed watchdog assets on Luna from a checkout of this repository.
set -Eeuo pipefail

readonly source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly library_dir=/usr/local/lib/luna-network-watchdog
readonly config_file=/etc/default/luna-network-watchdog

if (( EUID != 0 )); then
  echo 'Run this installer as root on Luna.' >&2
  exit 1
fi
if [[ $(hostname -s) != luna ]]; then
  echo 'Refusing to install: this installer is only for host luna.' >&2
  exit 1
fi

install -d -m 0755 "$library_dir"
install -m 0755 "$source_dir/luna-network-watchdog" "$library_dir/luna-network-watchdog"
install -m 0644 "$source_dir/luna-network-watchdog.service" /etc/systemd/system/luna-network-watchdog.service
install -m 0644 "$source_dir/luna-network-watchdog.timer" /etc/systemd/system/luna-network-watchdog.timer
if [[ ! -e "$config_file" ]]; then
  install -D -m 0644 "$source_dir/luna-network-watchdog.conf" "$config_file"
fi
systemctl daemon-reload
systemctl enable --now luna-network-watchdog.timer
systemctl status --no-pager luna-network-watchdog.timer
