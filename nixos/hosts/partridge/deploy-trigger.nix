{ pkgs, ... }:

let
  labDeployDispatch = pkgs.writeShellApplication {
    name = "lab-deploy-dispatch";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.gawk
      pkgs.glibc.bin
      pkgs.gnugrep
      pkgs.openssh
    ];
    text = ''
      set -euo pipefail

      log=/var/lib/lab-deploy/invocations.log
      mkdir -p "$(dirname "$log")"

      command_name="''${SSH_ORIGINAL_COMMAND:-lab-deploy-smoke}"
      printf '%s called %s from GitHub Actions\n' "$(date --iso-8601=seconds)" "$command_name" >> "$log"

      resolve_wren_target() {
        for _ in $(seq 1 30); do
          for candidate in wren wren.int.alcachofa.faith; do
            resolved="$(
              getent ahostsv4 "$candidate" 2>/dev/null \
                | grep ' STREAM ' \
                | awk 'NR == 1 { print $1 }'
            )"
            if [ -n "$resolved" ]; then
              printf '%s\n' "$resolved"
              return 0
            fi
          done

          sleep 2
        done

        printf 'could not resolve wren on the LAN after waiting for DHCP/DNS\n' >&2
        return 1
      }

      wait_for_wren_ssh() {
        wren_target="$1"
        shift

        for _ in $(seq 1 30); do
          if ssh \
            -o BatchMode=yes \
            -o ConnectTimeout=5 \
            -o IdentitiesOnly=yes \
            -o StrictHostKeyChecking=accept-new \
            "$@" \
            true >/dev/null 2>&1; then
            return 0
          fi

          sleep 2
        done

        printf 'wren resolved to %s but ssh did not come up in time\n' "$wren_target" >&2
        return 1
      }

      case "$command_name" in
        lab-deploy-smoke)
          printf 'lab-deploy-smoke called\n'
          ;;
        configure-wren)
          IFS= read -r ssh_key_b64
          IFS= read -r tailscale_oauth_secret

          if [ -z "$ssh_key_b64" ] || [ -z "$tailscale_oauth_secret" ]; then
            printf 'configure-wren requires a forwarded SSH key and Tailscale OAuth secret on stdin\n' >&2
            exit 1
          fi

          tmpdir="$(mktemp -d)"
          trap 'rm -rf "$tmpdir"' EXIT

          key_file="$tmpdir/wren-bootstrap"
          printf '%s' "$ssh_key_b64" | base64 -d > "$key_file"
          chmod 0600 "$key_file"

          cat >"$tmpdir/wren-bootstrap.sh" <<'REMOTE'
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

hostnamectl set-hostname wren

apt-get update
apt-get install -y ca-certificates curl gnupg nginx

install -d -m 0755 /usr/share/keyrings
curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg \
  | gpg --dearmor >/usr/share/keyrings/tailscale-archive-keyring.gpg
curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list \
  >/etc/apt/sources.list.d/tailscale.list

apt-get update
apt-get install -y tailscale

cat >/var/www/html/index.html <<'HTML'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>wren</title>
  </head>
  <body>
    <h1>Hello from wren</h1>
    <p>Zero-touch bootstrap VM on the lab tailnet.</p>
  </body>
</html>
HTML

systemctl enable --now nginx tailscaled

if tailscale ip -4 >/dev/null 2>&1; then
  tailscale up \
    --hostname=wren \
    --advertise-tags=tag:server \
    --ssh=false
else
  tailscale up \
    --auth-key="''${TAILSCALE_OAUTH_SECRET}?ephemeral=false&preauthorized=true" \
    --hostname=wren \
    --advertise-tags=tag:server \
    --ssh=false
fi
REMOTE

          wren_target="$(resolve_wren_target)"
          printf 'configure-wren target: %s\n' "$wren_target"
          wait_for_wren_ssh "$wren_target" \
            -i "$key_file" \
            "root@$wren_target"

          ssh \
            -i "$key_file" \
            -o BatchMode=yes \
            -o IdentitiesOnly=yes \
            -o StrictHostKeyChecking=accept-new \
            "root@$wren_target" \
            "TAILSCALE_OAUTH_SECRET='$tailscale_oauth_secret' bash -s" <"$tmpdir/wren-bootstrap.sh"

          printf 'configure-wren called\n'
          ;;
        verify-wren)
          curl --fail --silent http://wren.tailb35748.ts.net | grep -F "Hello from wren"
          printf 'verify-wren called\n'
          ;;
        *)
          printf 'unknown deploy command: %s\n' "$command_name" >&2
          exit 1
          ;;
      esac
    '';
  };
in
{
  users.groups.deploy = { };

  users.users.deploy = {
    isSystemUser = true;
    group = "deploy";
    home = "/var/lib/lab-deploy";
    createHome = true;
    shell = pkgs.bashInteractive;
    openssh.authorizedKeys.keys = [
      ''command="${labDeployDispatch}/bin/lab-deploy-dispatch",no-agent-forwarding,no-X11-forwarding,no-port-forwarding,no-pty ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFDFqPnPZHEGDv/vZ6HeXne0NxU7h1EO4sZAZEs1W/N2 github-actions-lab-deploy''
    ];
  };
}
