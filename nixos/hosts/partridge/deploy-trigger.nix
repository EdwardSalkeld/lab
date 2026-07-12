{ pkgs, ... }:

let
  labDeployDispatch = pkgs.writeShellApplication {
    name = "lab-deploy-dispatch";
    runtimeInputs = [
      pkgs.coreutils
    ];
    text = ''
      set -euo pipefail

      log=/var/lib/lab-deploy/invocations.log
      mkdir -p "$(dirname "$log")"

      command_name="''${SSH_ORIGINAL_COMMAND:-lab-deploy-smoke}"
      printf '%s called %s from GitHub Actions\n' "$(date --iso-8601=seconds)" "$command_name" >> "$log"

      case "$command_name" in
        lab-deploy-smoke)
          printf 'lab-deploy-smoke called\n'
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
