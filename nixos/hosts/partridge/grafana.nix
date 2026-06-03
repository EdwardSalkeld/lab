{ ... }:

let
  grafanaDomain = "grafana.alcachofa.faith";
  grafanaPort = 3001;
in
{
  alcachofa.partridge.reverseProxy.routes.${grafanaDomain}.port = grafanaPort;

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
        {
          name = "loki";
          uid = "ce6j6e2q9rapsa";
          type = "loki";
          access = "proxy";
          url = "http://blink.int.alcachofa.faith:3100";
          editable = true;
        }
      ];
    };
  };

}
