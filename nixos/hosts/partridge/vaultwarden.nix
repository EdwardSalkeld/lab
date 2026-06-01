{ ... }:

let
  vaultwardenDomain = "vault.alcachofa.faith";
  acmeHost = "partridge.int.alcachofa.faith";
  vaultwardenPort = 8222;
in
{
  fileSystems."/var/lib/vaultwarden" = {
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi3";
    fsType = "ext4";
  };

  security.acme.certs.${acmeHost}.extraDomainNames = [ vaultwardenDomain ];

  services.vaultwarden = {
    enable = true;
    config = {
      DATA_FOLDER = "/var/lib/vaultwarden";
      DOMAIN = "https://${vaultwardenDomain}";
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = vaultwardenPort;
      SIGNUPS_ALLOWED = true;
    };
  };

  services.nginx.virtualHosts.${vaultwardenDomain} = {
    forceSSL = true;
    useACMEHost = acmeHost;
    locations."/".proxyPass = "http://127.0.0.1:${toString vaultwardenPort}";
  };
}
