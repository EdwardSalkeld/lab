{ pkgs, ... }:

{
  imports = [
    ./bitwarden-mirror.nix
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
    ./mcm-db.nix
    ./web.nix
  ];

  networking.hostName = "partridge";
  networking.networkmanager.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
  alcachofa.journalToLoki = {
    enable = true;
    endpoint = "http://127.0.0.1:3100/loki/api/v1/push";
  };
  alcachofa.remoteDeploy.postSwitchHealthchecks = [ "grafana.service" ];

  services.tailscale = {
    enable = true;
    openFirewall = true;
    # Make the home LAN reachable to tailnet devices when the route is later
    # approved in the tailnet policy. Advertise /23 rather than the LAN's /24:
    # a client already on 10.4.1.0/24 keeps its more-specific direct LAN route.
    extraSetFlags = [ "--advertise-routes=10.4.0.0/23" ];
  };

  # A subnet router must be able to forward packets from tailscale0 to the LAN.
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

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
  users.users.billy.extraGroups = [
    "systemd-journal"
  ];
  environment.systemPackages = with pkgs; [
    git
    vim
    wget
  ];
}
