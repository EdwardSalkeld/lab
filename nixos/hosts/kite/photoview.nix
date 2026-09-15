{ ... }:

{
  services.photoview = {
    enable = true;
    host = "127.0.0.1";
    mediaPath = "/data/full/photos/archive";
    settings = {
      disableFaceRecognition = true;
      disableVideoEncoding = true;
      disableRawProcessing = true;
    };
  };

  users.users.photoview.extraGroups = [ "data" ];

  systemd.services.photoview = {
    after = [ "data.mount" ];
    wants = [ "data.mount" ];
    unitConfig.ConditionPathIsMountPoint = [ "/data" ];
  };
}
