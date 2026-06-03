{ config, lib, ... }:

let
  cfg = config.alcachofa.partridge.reverseProxy;
in
{
  options.alcachofa.partridge.reverseProxy = {
    acmeHost = lib.mkOption {
      type = lib.types.str;
      default = "partridge.int.alcachofa.faith";
      description = "Shared ACME certificate host used by Partridge proxied services.";
    };

    routes = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            host = lib.mkOption {
              type = lib.types.str;
              default = "127.0.0.1";
              description = "Upstream host to proxy to.";
            };

            port = lib.mkOption {
              type = lib.types.port;
              description = "Upstream port to proxy to.";
            };
          };
        }
      );
      default = { };
      description = "HTTPS reverse proxy routes served with the shared Partridge ACME certificate.";
    };
  };

  config = lib.mkIf (cfg.routes != { }) {
    security.acme.certs.${cfg.acmeHost}.extraDomainNames = lib.attrNames cfg.routes;

    services.nginx.virtualHosts = lib.mapAttrs
      (_domain: route: {
        forceSSL = true;
        useACMEHost = cfg.acmeHost;
        locations."/".proxyPass = "http://${route.host}:${toString route.port}";
      })
      cfg.routes;
  };
}
