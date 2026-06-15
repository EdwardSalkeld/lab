{ lib, ... }:

let
  proxy = port: {
    locations."/".proxyPass = "http://127.0.0.1:${toString port}";
  };
in
{
  networking.firewall.allowedTCPPorts = [ 80 ];

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;

    virtualHosts = lib.mapAttrs (_: port: proxy port) {
      "jellyfin.b.alcachofa.faith" = 8096;
      "navidrome.b.alcachofa.faith" = 4533;
      "photos.b.alcachofa.faith" = 3456;
    };
  };
}
