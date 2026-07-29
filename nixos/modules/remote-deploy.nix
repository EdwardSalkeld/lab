# Lets the orchestrator (fourth) trigger a rebuild of THIS host. fourth SSHes in
# as root with a key forced to the wrapper below, which rebuilds this host from
# the public flake on GitHub. Build-on-target: fourth is aarch64 and can't build
# x86 closures, so each host builds its own. A compromise of fourth's onward key
# can therefore only trigger a rebuild-from-main, never obtain a shell.
{ config, lib, pkgs, ... }:
let
  host = config.networking.hostName;
  cfg = config.alcachofa.remoteDeploy;
  postSwitchHealthchecks = lib.concatStringsSep " " (map lib.escapeShellArg cfg.postSwitchHealthchecks);
  labSwitch = pkgs.writeShellScript "lab-switch" ''
    set -euo pipefail
    /run/current-system/sw/bin/nixos-rebuild \
      switch --flake "github:EdwardSalkeld/lab#${host}" --refresh

    healthchecks=(${postSwitchHealthchecks})
    if [ "''${#healthchecks[@]}" -eq 0 ]; then
      exit 0
    fi

    sleep 5
    rollback_required=0
    for unit in "''${healthchecks[@]}"; do
      if ! /run/current-system/sw/bin/systemctl is-active --quiet "$unit"; then
        echo "post-switch health check failed: $unit is not active" >&2
        /run/current-system/sw/bin/systemctl --no-pager --full status "$unit" >&2 || true
        rollback_required=1
      fi
    done

    if [ "$rollback_required" -ne 0 ]; then
      echo "rolling back ${host} after failed post-switch health checks" >&2
      /run/current-system/sw/bin/nixos-rebuild switch --rollback
      exit 1
    fi
  '';
  # fourth's onward deploy public key — from creds/onward_ed25519.pub on fourth.
  fourthDeployKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEHQr6Slpjl/R7ZMoIf9CWb/Mmwjn5MaFXTpyqxUE952 fourth-deploy";
in
{
  options.alcachofa.remoteDeploy.postSwitchHealthchecks = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Systemd units that must be active after a remote deploy switch; otherwise the deploy rolls back.";
  };

  config.users.users.root.openssh.authorizedKeys.keys = [
    ''command="${labSwitch}",no-agent-forwarding,no-port-forwarding,no-X11-forwarding,no-pty ${fourthDeployKey}''
  ];
}
