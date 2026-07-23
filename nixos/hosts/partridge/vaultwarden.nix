{ ... }:

let
  vaultwardenDomain = "vault.alcachofa.faith";
  vaultwardenPort = 8222;
in
{
  fileSystems."/var/lib/vaultwarden" = {
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi3";
    fsType = "ext4";
  };

  alcachofa.partridge.reverseProxy.routes.${vaultwardenDomain}.port = vaultwardenPort;

  services.vaultwarden = {
    enable = true;
    config = {
      DATA_FOLDER = "/var/lib/vaultwarden";
      DOMAIN = "https://${vaultwardenDomain}";
      LOGIN_RATELIMIT_MAX_BURST = 20;
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = vaultwardenPort;
      SIGNUPS_ALLOWED = true;
    };
  };

}
