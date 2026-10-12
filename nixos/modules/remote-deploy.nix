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
    nix_store=/run/current-system/sw/bin/nix-store
    systemctl=/run/current-system/sw/bin/systemctl
    healthchecks=(${postSwitchHealthchecks})

    read -r command sha cache_name cache_key expected_path extra <<<"''${SSH_ORIGINAL_COMMAND:-}"
    if [[ "''${SSH_ORIGINAL_COMMAND:-}" == lab-switch ]]; then
      # Transitional compatibility while hosts are bootstrapped individually.
      # The existing main workflow still sends the bare command. Only this
      # legacy path retains build-on-target until #325 is merged.
      flake="github:EdwardSalkeld/lab#${host}"
      nix_options=(--refresh)
    elif [[ "$command" != lab-switch || ! "$sha" =~ ^[0-9a-f]{40}$ ||
          ! "$cache_name" =~ ^[a-z0-9][a-z0-9-]*$ ||
          ! "$cache_key" =~ ^[a-z0-9.-]+-1:[A-Za-z0-9+/=]+$ ||
          ! "$expected_path" =~ ^/nix/store/[a-z0-9]{32}-[A-Za-z0-9.+_-]+$ ||
          -n "''${extra:-}" ]]; then
      echo 'invalid lab-switch request' >&2
      exit 2
    else
      if [[ "$cache_name" != ${lib.escapeShellArg cfg.cacheName} ||
            "$cache_key" != ${lib.escapeShellArg cfg.cachePublicKey} ]]; then
        echo 'deploy cache does not match the installed trust configuration' >&2
        exit 2
      fi

      # The output path is checked after fetching so a stale or mismatched CI
      # result cannot be activated.
      source="github:EdwardSalkeld/lab/''${sha}"
      flake="''${source}#${host}"
      cache_url="https://''${cache_name}.cachix.org"
      nix_options=(--option extra-substituters "$cache_url"
                   --option extra-trusted-public-keys "$cache_key"
                   --option require-sigs true
                   --option builders ""
                   --option max-jobs 0)
      if ! actual_path="$("$nix" eval --raw "''${nix_options[@]}" \
          "''${source}#nixosConfigurations.${host}.config.system.build.toplevel.outPath")"; then
        echo "could not evaluate the CI-built output for ${host}" >&2
        exit 1
      fi
      if [[ "$actual_path" != "$expected_path" ]]; then
        echo "CI path mismatch for ${host}: expected $expected_path; got $actual_path" >&2
        exit 1
      fi
      # Realise the output path, not its derivation. This bypasses scaffolding
      # with allowSubstitutes=false and uses both Cachix and cache.nixos.org
      # (Cachix intentionally omits paths available from that upstream cache).
      if ! "$nix_store" --realise "$expected_path" "''${nix_options[@]}"; then
        echo "could not fetch the complete CI-built closure for ${host}" >&2
        exit 1
      fi
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

    # Capture the running system before nixos-rebuild can change the profile.
    # A failed switch may leave the profile advanced, or create no generation
    # at all. Rolling back by generation can therefore select the wrong system.
    if ! previous="$(readlink -e /run/current-system)"; then
      echo 'could not determine the running system; refusing to switch' >&2
      exit 1
    fi
    if ! recovery_root="$(mktemp -d /run/lab-switch-recovery.XXXXXX)"; then
      echo 'could not create a recovery GC root; refusing to switch' >&2
      exit 1
    fi
    trap 'rm -rf -- "$recovery_root"' EXIT
    if ! "$nix_store" --add-root "$recovery_root/system" --indirect \
        --realise "$previous" --option builders "" --option max-jobs 0; then
      echo 'could not retain the running system for recovery; refusing to switch' >&2
      exit 1
    fi
    nix_env="$previous/sw/bin/nix-env"
    systemctl="$previous/sw/bin/systemctl"
    recovered=0
    restore_previous() {
      # Try once even if both switch and health checks fail. This activates an
      # existing closure without evaluating a flake or requiring nixos-config.
      [[ "$recovered" == 0 ]] || return 0
      recovered=1
      "$nix_env" --profile /nix/var/nix/profiles/system --set "$previous" || \
        echo 'restoring the previous system profile failed' >&2
      "$previous/bin/switch-to-configuration" switch || \
        echo 'activating the previous system also failed' >&2
    }

    rc=0
    if ! "$nixos_rebuild" switch --flake "$flake" "''${nix_options[@]}"; then
      echo "nixos-rebuild switch failed; restoring ${host} to $previous" >&2
      rc=1
      restore_previous
    fi

    if [ "''${#healthchecks[@]}" -eq 0 ]; then
      exit "$rc"
    fi

    sleep 5
    if ! units_healthy; then
      echo "post-switch health check failed on ${host}; rolling back" >&2
      rc=1
      restore_previous
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
      lab-switch | lab-switch\ *)
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
  options.alcachofa.remoteDeploy.cacheName = lib.mkOption {
    type = lib.types.str;
    default = "brokensbone-main";
    description = "Trusted Cachix cache for CI-built system deployments.";
  };
  options.alcachofa.remoteDeploy.cachePublicKey = lib.mkOption {
    type = lib.types.str;
    default = "brokensbone-main.cachix.org-1:4dEguXUK+SK1OJBN9Q3AD4Dpl+tKVsRwqf3HJQy8Bd4=";
    description = "Installed trust anchor; a deploy request cannot replace this key.";
  };
  options.alcachofa.remoteDeploy.postSwitchHealthchecks = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Systemd units that must be active after a remote deploy switch; otherwise the deploy rolls back.";
  };

  config.users.users.root.openssh.authorizedKeys.keys = [
    ''command="${remoteCommand}",no-agent-forwarding,no-port-forwarding,no-X11-forwarding,no-pty ${fourthDeployKey}''
  ];
}
