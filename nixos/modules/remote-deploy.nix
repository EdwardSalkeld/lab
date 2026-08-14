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
    # Deliberately NOT `set -e`: a failed switch must never abort this script
    # before recovery runs, or a half-applied switch (services stopped, not
    # restarted) silently downs the host. We handle failures explicitly and
    # guarantee the health-checked units are running before exit.
    set -uo pipefail
    nixos_rebuild=/run/current-system/sw/bin/nixos-rebuild
    systemctl=/run/current-system/sw/bin/systemctl
    healthchecks=(${postSwitchHealthchecks})

    units_healthy() {
      local unit
      for unit in "''${healthchecks[@]}"; do
        "$systemctl" is-active --quiet "$unit" || return 1
      done
      return 0
    }
    start_units() {
      local unit
      for unit in "''${healthchecks[@]}"; do
        "$systemctl" start "$unit" || true
      done
    }

    rc=0
    if ! "$nixos_rebuild" switch --flake "github:EdwardSalkeld/lab#${host}" --refresh; then
      echo "nixos-rebuild switch failed; rolling back ${host} to the last generation" >&2
      rc=1
      "$nixos_rebuild" switch --rollback || echo "rollback switch also failed" >&2
    fi

    if [ "''${#healthchecks[@]}" -eq 0 ]; then
      exit "$rc"
    fi

    sleep 5
    if ! units_healthy; then
      echo "post-switch health check failed on ${host}; rolling back" >&2
      rc=1
      "$nixos_rebuild" switch --rollback || echo "rollback switch also failed" >&2
      sleep 5
    fi

    # Last resort: if a unit is still down (e.g. the rollback switch itself hit
    # an activation error), start it directly so a deploy never leaves the host
    # with critical services stopped.
    if ! units_healthy; then
      echo "health-checked units still down after rollback; starting them directly" >&2
      rc=1
      start_units
    fi

    exit "$rc"
  '';
  nixGc = pkgs.writeShellScript "lab-nix-gc" ''
    set -euo pipefail
    systemctl=/run/current-system/sw/bin/systemctl

    echo "Disk usage before Nix GC on ${host}:"
    ${pkgs.coreutils}/bin/df -h /
    "$systemctl" start nix-gc.service
    echo "Disk usage after Nix GC on ${host}:"
    ${pkgs.coreutils}/bin/df -h /
  '';
  remoteCommand = pkgs.writeShellScript "lab-remote-command" ''
    case "''${SSH_ORIGINAL_COMMAND:-}" in
      lab-switch)
        exec ${labSwitch}
        ;;
      nix-gc)
        exec ${nixGc}
        ;;
      *)
        echo "unsupported remote command" >&2
        exit 2
        ;;
    esac
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
    ''command="${remoteCommand}",no-agent-forwarding,no-port-forwarding,no-X11-forwarding,no-pty ${fourthDeployKey}''
  ];
}
