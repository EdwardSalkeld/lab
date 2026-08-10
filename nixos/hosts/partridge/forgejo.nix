{ ... }:

let
  forgejoDomain = "code.alcachofa.faith";
  forgejoPort = 3000;
in
{
  alcachofa.partridge.reverseProxy.routes.${forgejoDomain}.port = forgejoPort;

  # Forgejo git SSH (built-in server on 2222, configured below).
  networking.firewall.allowedTCPPorts = [ 2222 ];

  services.forgejo = {
    enable = true;
    database.type = "postgres";
    lfs.enable = true;
    stateDir = "/srv/code/forgejo";
    useWizard = false;

    settings = {
      server = {
        DOMAIN = forgejoDomain;
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = forgejoPort;
        ROOT_URL = "https://${forgejoDomain}/";

        DISABLE_SSH = false;
        START_SSH_SERVER = true;
        SSH_DOMAIN = forgejoDomain;
        SSH_PORT = 2222;
        SSH_LISTEN_PORT = 2222;
        SSH_USER = "git";
      };

      service = {
        DISABLE_REGISTRATION = true;
        REQUIRE_SIGNIN_VIEW = true;
      };

      actions = {
        ENABLED = true;
        # Resolve `uses:` actions (actions/checkout@v4 etc.) from GitHub, since
        # private repos moving onto this Forgejo will reference them.
        DEFAULT_ACTIONS_URL = "github";
      };
    };
  };
}
