{ ... }:

let
  grafanaDomain = "grafana.a.f";
  acmeHost = "partridge.int.alcachofa.faith";
  grafanaPort = 3001;
in
{
  services.postgresql = {
    ensureDatabases = [ "grafana" ];
    ensureUsers = [
      {
        name = "grafana";
        ensureDBOwnership = true;
      }
    ];
  };

  services.grafana = {
    enable = true;

    settings = {
      server = {
        domain = grafanaDomain;
        http_addr = "127.0.0.1";
        http_port = grafanaPort;
        root_url = "https://${grafanaDomain}/";
      };

      database = {
        type = "postgres";
        host = "/run/postgresql";
        name = "grafana";
        user = "grafana";
      };

      users = {
        allow_sign_up = false;
        allow_org_create = false;
      };
    };

    provision.datasources.settings = {
      apiVersion = 1;
      datasources = [
        {
          name = "prometheus";
          uid = "fdp9rmnopl3wgf";
          type = "prometheus";
          access = "proxy";
          url = "http://127.0.0.1:9090";
          isDefault = true;
          editable = true;
        }
      ];
    };
  };

  services.nginx.virtualHosts.${grafanaDomain} = {
    forceSSL = true;
    useACMEHost = acmeHost;
    locations."/".proxyPass = "http://127.0.0.1:${toString grafanaPort}";
  };
}
