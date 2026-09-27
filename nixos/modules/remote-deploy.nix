# Lets fourth trigger a pinned switch of a CI-built system. The forced key has
# no shell access and only accepts a commit and its expected output.
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
    nix=/run/current-system/sw/bin/nix
    systemctl=/run/current-system/sw/bin/systemctl
    healthchecks=(${postSwitchHealthchecks})

    read -r command sha cache_name cache_key expected_path extra <<<"''${SSH_ORIGINAL_COMMAND:-}"
    if [[ "$command" != lab-switch || ! "$sha" =~ ^[0-9a-f]{40}$ ||
          ! "$cache_name" =~ ^[a-z0-9][a-z0-9-]*$ ||
          ! "$cache_key" =~ ^[a-z0-9.-]+-1:[A-Za-z0-9+/=]+$ ||
          ! "$expected_path" =~ ^/nix/store/[a-z0-9]{32}-[A-Za-z0-9.+_-]+$ ||
          -n "''${extra:-}" ]]; then
      echo 'invalid lab-switch request' >&2
      exit 2
    fi

    # The output path is checked after fetching so a stale or mismatched CI
    # result cannot be activated.
    source="github:EdwardSalkeld/lab/''${sha}"
    flake="''${source}#${host}"
    cache_url="https://''${cache_name}.cachix.org"
    nix_options=(--option extra-substituters "$cache_url"
                 --option extra-trusted-public-keys "$cache_key"
                 --option builders ""
                 --option max-jobs 0)
    if ! actual_path="$("$nix" build --no-link --print-out-paths
        "''${nix_options[@]}" "''${source}#nixosConfigurations.${host}.config.system.build.toplevel")"; then
      echo "could not fetch the complete CI-built closure for ${host}" >&2
      exit 1
    fi
    if [[ "$actual_path" != "$expected_path" ]]; then
      echo "CI path mismatch for ${host}: expected $expected_path; got $actual_path" >&2
      exit 1
    fi

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
    if ! "$nixos_rebuild" switch --flake "$flake" "''${nix_options[@]}"; then
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
      lab-switch\ *)
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
