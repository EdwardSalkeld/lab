{ ... }:

let
  forgejoDomain = "code.alcachofa.faith";
  forgejoPort = 3000;
in
{
  alcachofa.partridge.reverseProxy.routes.${forgejoDomain}.port = forgejoPort;

  # Reach the Forgejo built-in SSH server on any interface. tailscale0 is
  # already trusted; opening 2222 explicitly also covers LAN access, so SSH
  # keeps working if local DNS is pointed at partridge's LAN IP.
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

        # SSH via Forgejo's built-in server on 2222 — the host's own sshd owns
        # 22. 2222 is opened in the firewall below so it works whether clients
        # reach partridge over tailscale (today code.alcachofa.faith resolves to
        # its tailscale IP) or over the LAN (if local DNS is later pointed at
        # partridge's LAN IP). Not public: partridge has no public interface and
        # the router forwards nothing to it. Clone URLs:
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
