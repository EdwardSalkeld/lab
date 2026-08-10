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
        DOMAIN = forgejoDomain;
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = forgejoPort;
        ROOT_URL = "https://${forgejoDomain}/";

        # SSH via Forgejo's built-in server on 2222 — the host's own sshd owns
        # 22. No firewall opening needed: code.alcachofa.faith resolves to
        # partridge's tailscale IP and tailscale0 is the trusted firewall
        # interface, so the git SSH port is reachable over the tailnet only,
        # never exposed on the LAN or publicly. Clone URLs:
        # ssh://git@code.alcachofa.faith:2222/owner/repo.git
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
