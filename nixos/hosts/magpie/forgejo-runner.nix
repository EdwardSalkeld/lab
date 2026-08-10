{ config, pkgs, lib, ... }:

# Docker-mode Forgejo Actions runner, co-located on magpie. magpie is the "dev"
# host and sits 99% idle inside its 8 GB envelope, so in-house CI for private
# repos (moving off GitHub onto partridge's Forgejo) lives in that slack rather
# than in a new VM — nothing changes at the Proxmox level.
#
# Isolation: the upstream module runs the runner as a DynamicUser ("gitea-runner")
# and adds *only* that user to the `docker` group. The chatting service users
# (bbmb/handler/worker) and billy are deliberately left out, so no part of the
# chatting runtime can reach the Docker socket (which is effectively root).
#
# ── Finishing the setup (one-time, in this order) ────────────────────────────
#   1. terraform apply  → attaches the 30 GB scsi2 CI disk to magpie.
#   2. On magpie, format it and label it `dockerdata` (identify the new blank
#      disk with `lsblk`; it is the one with no filesystem):
#        sudo mkfs.ext4 -L dockerdata /dev/sdX
#   3. In Forgejo (code.alcachofa.faith) → Site admin → Actions → Runners →
#      "Create new runner", copy the registration token.
#   4. Encrypt it into ./secrets/forgejo-runner.json (see the .example file):
#        sops nixos/hosts/magpie/secrets/forgejo-runner.json
#   5. Merge → the deploy mounts /var/lib/docker on the CI disk, starts Docker,
#      and the runner registers itself against Forgejo.
#
# Everything below is gated on that secret existing, so merging this module
# before step 4 is a no-op (the lab auto-deploys on merge; a runner wired to a
# missing sops secret would otherwise fail activation).

let
  tokenSopsFile = ./secrets/forgejo-runner.json;
  runnerEnabled = builtins.pathExists tokenSopsFile;
in
{
  config = lib.mkIf runnerEnabled {
    # Docker exists solely to back the runner. Its data-root, /var/lib/docker,
    # is mounted on the dedicated magpie-ci disk (hardware-configuration.nix) so
    # CI image/layer churn can never fill magpie's 24 GB OS root.
    virtualisation.docker.enable = true;
    # 25.11's default docker (28.x) is flagged unmaintained/EOL, which fails
    # evaluation; pin the maintained line instead of whitelisting a stale one.
    virtualisation.docker.package = pkgs.docker_29;

    # magpie is not on partridge's tailnet, so MagicDNS points
    # code.alcachofa.faith at partridge's unreachable tailscale IP. Pin it to
    # partridge's LAN address instead: both VMs share the Proxmox bridge, and
    # nginx serves the Forgejo vhost there with a cert valid for this name.
    # NOTE: 10.4.1.130 is partridge's current DHCP lease — worth a static
    # reservation so this can't drift.
    networking.hosts."10.4.1.130" = [ "code.alcachofa.faith" ];

    # The module consumes the registration token as an *env file* (TOKEN=...),
    # not a raw value, so render it through a sops template (as chatting does).
    sops.secrets."forgejo-runner/token" = {
      sopsFile = tokenSopsFile;
      key = "token";
    };
    sops.templates."forgejo-runner.env".content = ''
      TOKEN=${config.sops.placeholder."forgejo-runner/token"}
    '';

    services.gitea-actions-runner = {
      # forgejo-runner is the Forgejo-native fork; it ships an `act_runner`
      # symlink, which the upstream NixOS module invokes.
      package = pkgs.forgejo-runner;
      instances.magpie = {
        enable = true;
        name = "magpie";
        url = "https://code.alcachofa.faith";
        tokenFile = config.sops.templates."forgejo-runner.env".path;
        # Map the runs-on labels private repos will use onto Docker images. The
        # node images bundle bash/git/nodejs, which most actions assume. The
        # runner re-registers automatically when these change; tune per project.
        labels = [
          "ubuntu-latest:docker://node:22-bookworm"
          "ubuntu-22.04:docker://node:22-bookworm"
          "docker:docker://node:22-bookworm"
        ];
      };
    };
  };
}
