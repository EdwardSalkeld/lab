{ ... }:

let
  forgejoDomain = "code.alcachofa.faith";
  forgejoPort = 3000;
in
{
  alcachofa.partridge.reverseProxy.routes.${forgejoDomain}.port = forgejoPort;

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
}
