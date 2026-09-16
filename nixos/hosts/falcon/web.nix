# Falcon has no address in the int zone, being the one host outside the house,
# so its landing page answers on the tailnet name instead.
{ config, ... }:

let
  falconTailnetDomain = "falcon.ts.alcachofa.faith";
in
{
  # A certificate of its own rather than another name on Navidrome's: the two
  # have nothing to do with each other, and sharing would couple this module to
  # whichever one happens to define the cert. DNS-01 is required either way —
  # the name resolves to a tailnet address no ACME server can reach.
  security.acme.certs.${falconTailnetDomain} = {
    dnsProvider = "cloudflare";
    environmentFile = config.sops.templates."acme-cloudflare.env".path;
    group = "nginx";
  };

  alcachofa.holdingPage = {
    enable = true;
    domains = [ falconTailnetDomain ];
    useACMEHost = falconTailnetDomain;
    image = ./bird.jpg;
    plate = "Peregrine Falcon, Falco peregrinus";
    alt = "A peregrine falcon on a rock, facing the viewer, slate-grey above and barred below.";
    credit = "Peregrine Falcon, <i>Falco peregrinus</i>. Drawn by G. E. Lodge, lithographed by J. Smit, from Lilford's <i>Coloured Figures of the Birds of the British Islands</i> (1885-97). Public domain, via Wikimedia Commons.";
  };
}
