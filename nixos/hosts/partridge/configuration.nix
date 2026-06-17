{ pkgs, ... }:

{
  imports = [
    ./bitwarden-mirror.nix
    ./deploy-trigger.nix
    ./forgejo.nix
    ./grafana.nix
    ./hardware-configuration.nix
    ./loki.nix
    ./octopus-dl.nix
    ./prometheus.nix
    ./reverse-proxy.nix
    ./scheduler-db.nix
    ./vaultwarden.nix
    ./web.nix
    ./exercise-tracker.nix
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

  environment.systemPackages = with pkgs; [
    git
    vim
    wget
  ];
}
