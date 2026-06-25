# Lets the orchestrator (fourth) trigger a rebuild of THIS host. fourth SSHes in
# as root with a key forced to the wrapper below, which rebuilds this host from
# the public flake on GitHub. Build-on-target: fourth is aarch64 and can't build
# x86 closures, so each host builds its own. A compromise of fourth's onward key
# can therefore only trigger a rebuild-from-main, never obtain a shell.
{ config, pkgs, ... }:
let
  host = config.networking.hostName;
  labSwitch = pkgs.writeShellScript "lab-switch" ''
    set -euo pipefail
    exec /run/current-system/sw/bin/nixos-rebuild \
      switch --flake "github:EdwardSalkeld/lab#${host}" --refresh
  '';
  # fourth's onward deploy public key — from creds/onward_ed25519.pub on fourth.
  fourthDeployKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEHQr6Slpjl/R7ZMoIf9CWb/Mmwjn5MaFXTpyqxUE952 fourth-deploy";
in
{
  users.users.root.openssh.authorizedKeys.keys = [
    ''command="${labSwitch}",no-agent-forwarding,no-port-forwarding,no-X11-forwarding,no-pty ${fourthDeployKey}''
  ];
}
