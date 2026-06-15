{ ... }:

{
  fileSystems."/media" = {
    device = "/mnt/ext2tb/1";
    options = [
      "bind"
      "nofail"
    ];
  };

  fileSystems."/media3" = {
    device = "/mnt/ext2tb/3";
    options = [
      "bind"
      "nofail"
    ];
  };

  fileSystems."/media4" = {
    device = "/mnt/ext2tb/4";
    options = [
      "bind"
      "nofail"
    ];
  };

  fileSystems."/music" = {
    device = "/mnt/ssd4tb/partial/record-library/library";
    options = [
      "bind"
      "nofail"
    ];
  };

  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

  systemd.services.jellyfin = {
    environment = {
      JELLYFIN_PublishedServerUrl = "http://home.alcachofa.uk/jellyfin";
    };
    requiresMountsFor = [
      "/media"
      "/media3"
      "/media4"
      "/music"
    ];
  };

  services.navidrome = {
    enable = true;
    openFirewall = true;
    settings = {
      Address = "0.0.0.0";
      Port = 4533;
      MusicFolder = "/music";
    };
  };

  systemd.services.navidrome.requiresMountsFor = [
    "/music"
  ];
}
