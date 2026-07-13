{ pkgs, ... }:

{
  imports = [
    ./bitwarden-mirror.nix
    ./deploy-trigger.nix
    ./forgejo.nix
    ./grafana.nix
    ./hardware-configuration.nix
    ./exercise-tracker.nix
    ./loki.nix
    ./linear-export.nix
    ./octopus-dl.nix
    ./opnsense-exporter.nix
    ./postgres-readonly.nix
    ./prometheus.nix
    ./reverse-proxy.nix
    ./scheduler-db.nix
    ./vaultwarden.nix
    ./web.nix
  ];

  networking.hostName = "partridge";
  networking.networkmanager.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  fileSystems."/srv/code" = {
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1";
    fsType = "ext4";
  };

  fileSystems."/var/lib/postgresql" = {
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi2";
    fsType = "ext4";
  };

  services.postgresql.enable = true;

  services.prometheus.exporters.postgres = {
    enable = true;
    openFirewall = true;
    runAsLocalSuperUser = true;
  };

  users.users.edward.packages = with pkgs; [
    tree
  ];
  users.users.edward.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgAC7g5CoTIOcrTpzDqFylWrcMGJIqOQC2RrYcWQzhD4NTB8Uh5ZHhR0LMfRhFXivIs3TY+bAe4ov7FODCOimL6irSoj6Pd/2La3o3hXGz2u/l1/7sLWxtG3H7k2QCOHacVzZUznJpn4rAGtfq2w8cmF/RNO1kc/ZncaIlh2TZ8f3D5cAEKUV2f7YN40d9MSnXNgg6YRgL91wfWDO7DMuWUi5UTqcH/3NBcJXsrTEQ7TT10ISabIVoLNROoAiORZY83iy1fYSGN3u3tapxV1EhbW9nsluBonW57jPavUuQIrPhsbDdTvqOiWgC/9XqthHejj7r1q0lo+EZqmqK7wSQMXR4aNt8TMGLWwt6GvM0fbUq/RNs1/C9R5wKu+pmo0CHE+J53HXCzkEFxgOMAqk/dhTSF2aOgUOUFfigVHs2EniUtaEDGCoKbM28kB0UbSnJruGGyK9znu9SJuR2dGM0gk35TfPDJPzGZFKK5ofwbUnV0MqO4zCUrRPYHgCwDCgkw== billy@chatting"
  ];

  environment.systemPackages = with pkgs; [
    git
    vim
    wget
  ];
}
