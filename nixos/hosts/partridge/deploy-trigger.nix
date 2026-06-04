{ pkgs, ... }:

let
  labDeploySmoke = pkgs.writeShellApplication {
    name = "lab-deploy-smoke";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      log=/var/lib/lab-deploy/invocations.log
      mkdir -p "$(dirname "$log")"
      printf '%s called lab-deploy-smoke from GitHub Actions\n' "$(date --iso-8601=seconds)" >> "$log"
      printf 'lab-deploy-smoke called\n'
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
      ''command="${labDeploySmoke}/bin/lab-deploy-smoke",no-agent-forwarding,no-X11-forwarding,no-port-forwarding,no-pty ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFDFqPnPZHEGDv/vZ6HeXne0NxU7h1EO4sZAZEs1W/N2 github-actions-lab-deploy''
    ];
  };
}
