#!/usr/bin/env bash
# Run as root ON the Debian guest, from a checkout of the reviewed Lab commit.
# Input credentials are staged separately, never in Terraform/cloud-init state.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_dir="$repo_root/services/zulip"
secret_file="${1:?Usage: sudo scripts/zulip-bootstrap.sh /run/zulip-secrets.conf}"
test "$EUID" -eq 0 || { echo 'Run as root on the Debian guest.' >&2; exit 1; }
# shellcheck source=/dev/null
source /etc/os-release
test "$ID" = debian && test "$VERSION_ID" = 13 || {
  echo 'This bootstrap targets the dedicated Debian 13 guest only.' >&2; exit 1;
}
test -s "$secret_file"
# Reject partial credentials before changing the guest.
python3 - "$secret_file" <<'PY'
import configparser
import sys

config = configparser.RawConfigParser()
config.read(sys.argv[1])
required = (
    'postgres_password', 'secret_key', 'avatar_salt', 'shared_secret',
    'camo_key', 'rabbitmq_password', 'memcached_password', 'redis_password',
    'email_password',
)
if any(not config.get('secrets', name, fallback='') for name in required):
    raise SystemExit('Incomplete secrets file; re-stage it from Partridge.')
PY
# shellcheck source=services/zulip/release.env
source "$config_dir/release.env"
current=/home/zulip/deployments/current
if [ -x "$current/manage.py" ]; then
  installed_version="$(sed -n 's/^ZULIP_VERSION = "\([^"]*\)".*/\1/p' "$current/version.py")"
  test "$installed_version" = "$ZULIP_VERSION" || {
    echo 'Use the documented Zulip upgrade procedure before reapplying a new release pin.' >&2
    exit 1
  }
fi
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl git nftables qemu-guest-agent
if [ -e /dev/virtio-ports/org.qemu.guest_agent.0 ]; then
  systemctl start qemu-guest-agent
fi

if [ ! -e /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 0600 /swapfile
  mkswap /swapfile
fi
grep -qE '^/swapfile[[:space:]]' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
swapon /swapfile 2>/dev/null || swapon --show=NAME --noheadings | grep -qx /swapfile

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
curl --fail --location --retry 3 \
  "https://download.zulip.com/server/zulip-server-$ZULIP_VERSION.tar.gz" \
  --output "$work_dir/release.tar.gz"
printf '%s  %s\n' "$ZULIP_SHA256" "$work_dir/release.tar.gz" | sha256sum --check --status
tar -xzf "$work_dir/release.tar.gz" -C "$work_dir"
release_dir="$work_dir/zulip-server-$ZULIP_VERSION"
test -f "$release_dir/zproject/prod_settings_template.py"

# Configuration = pinned upstream defaults plus our versioned overrides.
install -d -m 0755 /etc/zulip
id -u zulip >/dev/null 2>&1 || useradd -m zulip --home-dir /home/zulip
cat "$release_dir/zproject/prod_settings_template.py" "$config_dir/settings.py" > /etc/zulip/settings.py
install -m 0644 "$config_dir/zulip.conf" /etc/zulip/zulip.conf
install -o zulip -g zulip -m 0600 "$secret_file" /etc/zulip/zulip-secrets.conf

if [ -x "$current/manage.py" ]; then
  chown zulip:zulip /etc/zulip/settings.py /etc/zulip/zulip-secrets.conf
  "$current/scripts/zulip-puppet-apply"
else
  "$release_dir/scripts/setup/install" \
    --hostname=zulip.int.alcachofa.faith --email=edsalkeld@alcachofa.faith \
    --self-signed-cert --no-init-db --no-overwrite-settings \
    --puppet-classes=zulip::profile::standalone_nodb,zulip::process_fts_updates \
    --postgresql-version=17 --postgresql-database-name=zulip --postgresql-database-user=zulip \
    --no-push-notifications --no-submit-usage-statistics --agree-to-terms-of-service
fi
chown zulip:zulip /etc/zulip/zulip-secrets.conf
chmod 0600 /etc/zulip/zulip-secrets.conf
# Migrate an empty or restored database without dropping/recreating it.
su zulip -c "$current/scripts/setup/initialize-database --quiet"
install -m 0644 "$config_dir/nftables.conf" /etc/nftables.conf
nft --check --file /etc/nftables.conf
systemctl enable --now nftables
systemctl restart nftables
rm -f "$secret_file"
echo 'Zulip provisioned. Use generate_realm_creation_link once for initial organization setup.'
