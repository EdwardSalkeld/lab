{ ... }:

let
  forgejoDomain = "code.alcachofa.faith";
  acmeHost = "partridge.int.alcachofa.faith";
  forgejoPort = 3000;
in
{
  security.acme.certs.${acmeHost}.extraDomainNames = [ forgejoDomain ];

  services.forgejo = {
    enable = true;
    database.type = "postgres";
    lfs.enable = true;
    stateDir = "/srv/code/forgejo";
    useWizard = false;

    settings = {
      server = {
        DISABLE_SSH = true;
        DOMAIN = forgejoDomain;
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = forgejoPort;
        ROOT_URL = "https://${forgejoDomain}/";
      };

      service = {
        DISABLE_REGISTRATION = true;
        REQUIRE_SIGNIN_VIEW = true;
      };
    };
  };

  services.nginx.virtualHosts.${forgejoDomain} = {
    forceSSL = true;
    useACMEHost = acmeHost;
    locations."/".proxyPass = "http://127.0.0.1:${toString forgejoPort}";
  };
}
