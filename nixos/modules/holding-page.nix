# A host's landing page: one antique plate of the bird it is named after, the
# hostname underneath. Nothing else — these names get typed by hand and landing
# on a default nginx page gives no clue which machine answered.
{ config, lib, pkgs, ... }:

let
  cfg = config.alcachofa.holdingPage;

  # Named substitutions rather than substituteAll, which would sweep in every
  # lowercase variable in the build environment — including `name`, which is
  # the derivation's own.
  site = pkgs.runCommand "holding-page-${cfg.name}" { } ''
    mkdir -p "$out"
    cp ${cfg.image} "$out/bird.jpg"
    substitute ${./holding-page/index.html.in} "$out/index.html" \
      --subst-var-by name ${lib.escapeShellArg cfg.name} \
      --subst-var-by plate ${lib.escapeShellArg cfg.plate} \
      --subst-var-by alt ${lib.escapeShellArg cfg.alt} \
      --subst-var-by credit ${lib.escapeShellArg cfg.credit}
  '';
in
{
  options.alcachofa.holdingPage = {
    enable = lib.mkEnableOption "the bird plate landing page for this host";

    domains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Virtual hosts to serve the landing page on.";
    };

    useACMEHost = lib.mkOption {
      type = lib.types.str;
      description = "Existing certificate to serve with; every domain above must be on it.";
    };

    image = lib.mkOption {
      type = lib.types.path;
      description = "The plate, cropped to the printed page.";
    };

    name = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "Name shown beneath the plate.";
    };

    plate = lib.mkOption {
      type = lib.types.str;
      description = "Plate title as printed, shown to screen readers via the image alt text.";
    };

    alt = lib.mkOption {
      type = lib.types.str;
      description = "Description of the illustration itself.";
    };

    credit = lib.mkOption {
      type = lib.types.str;
      description = "Artist, work and licence. CC BY plates are only legal to serve with this.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.nginx.virtualHosts = lib.genAttrs cfg.domains (_domain: {
      forceSSL = true;
      inherit (cfg) useACMEHost;
      root = site;
    });
  };
}
