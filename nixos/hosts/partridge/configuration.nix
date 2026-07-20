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
    ./wantlist-db.nix
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
  users.users.billy = {
    isNormalUser = true;
    extraGroups = [
      "systemd-journal"
      "wheel"
    ];
    openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7g5CoTIOcrTpzDqFylWrcMGJIqOQC2RrYcWQzhD4NTB8Uh5ZHhR0LMfRhFXivIs3TY+bAe4ov7FODCOimL6irSoj6Pd/2La3o3hXGz2u/l1/7sLWxtG3H7k2QCOHacVzZUznJpn4rAGtfq2w8cmF/RNO1kc/ZncaIlh2TZ8f3D5cAEKUV2f7YN40d9MSnXNgg6YRgL91wfWDO7DMuWUi5UTqcH/3NBcJXsrTEQ7TT10ISabIVoLNROoAiORZY83iy1fYSGN3u3t72qcVdRIW1vZ7JbgaJ1ue4z2r1LkCKz4bGw3U76joloAv/V6rYR3o4+69atJaPhGapqiu8EkDF0eGjbfEzBi1sLehrzNH21Kv0TbNfwvUecCrvqZqNAhxPiedx1ws5BBcYDjAKpP3YU0hdmjoFDlBX4oFR7NhJ4lLWhAxgqCmzNvJAdFG0pya7hhsivc57vUibkdnRjNIJN+U3zwyT8xmRSiuaH8G1J1dDKjuMwlK0T2B4AsAwoJM= billy@chatting"
    ];
  };

  environment.systemPackages = with pkgs; [
    git
    vim
    wget
  ];
}
