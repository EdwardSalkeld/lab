{ config, lib, ... }:

{
  sops.secrets."photoprism/admin_password" = {
    key = "admin_password";
    sopsFile = ./secrets/photoprism.yaml;
  };

  services.photoprism = {
    enable = true;
    address = "127.0.0.1";
    originalsPath = "/data/full/photos/archive";
    passwordFile = config.sops.secrets."photoprism/admin_password".path;
    settings = {
      PHOTOPRISM_READONLY = "true";
      PHOTOPRISM_DISABLE_WEBDAV = "true";
      PHOTOPRISM_SITE_URL = "https://photos.alcachofa.faith/";
    };
  };

  systemd.services.photoprism = {
    after = [ "data.mount" ];
    wants = [ "data.mount" ];
    unitConfig.ConditionPathIsMountPoint = [ "/data" ];
    serviceConfig = {
      SupplementaryGroups = [ "data" ];
      # The upstream module permits writes to originals. This gallery only
      # indexes the migrated collection, so keep its mutable state separate.
      ReadWritePaths = lib.mkForce [ "/var/lib/photoprism" ];
      ReadOnlyPaths = [ "/data/full/photos/archive" ];
    };
  };
}
