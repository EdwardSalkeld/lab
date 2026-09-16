# Host Landing Pages

Every host answers on its own hostname with a single antique plate of the bird
it is named after and the hostname underneath. Without it a host answers on its
own name with whichever vhost nginx matched first, which tells you nothing about
which machine you reached.

The module is `nixos/modules/holding-page.nix`; the page itself is
`nixos/modules/holding-page/index.html.in`.

## Where the plates come from

All four are from **Lilford's *Coloured Figures of the Birds of the British
Islands*** (1885–97), scanned by the Biodiversity Heritage Library and held on
Wikimedia Commons. Sticking to one work is deliberate: the pages read as a set
rather than four unrelated pictures. It covers British birds comprehensively, so
a new host named after one will almost certainly be in there.

Beware that the Commons file titles for this work are just accession numbers —
`Coloured figures of the birds of the British Islands - issued by Lord Lilford
(6029164994).jpg` — so you cannot find a bird by filename. Search the API and
check the licence per file, because scans of the same public-domain work are
tagged inconsistently:

```sh
curl -sG 'https://commons.wikimedia.org/w/api.php' \
  --data-urlencode action=query --data-urlencode format=json \
  --data-urlencode list=search --data-urlencode srnamespace=6 \
  --data-urlencode 'srsearch=Lilford heron Ardea'
```

Then fetch `prop=imageinfo&iiprop=url|size|extmetadata` for the hits to get the
direct URL, dimensions and `LicenseShortName`. The API rate-limits aggressively;
space the calls a couple of seconds apart and set a real User-Agent.

**Licences vary within the work.** Most plates are public domain, but some scans
are CC BY 2.0 — partridge's is. CC BY is fine to use, but the credit is then
legally required rather than merely polite, so fill in `credit` either way.

**Look at the image before choosing it.** Some plates put three species on one
sheet, and at least one has a raven eating a dead ptarmigan, which is not what
you want greeting you on a hostname.

## Preparing the image

Trim the scanned page edges and the page curl, but **keep the printed caption** —
it is part of the plate and reads like a museum label above the hostname.

```python
from PIL import Image
im = Image.open("plate.jpg").convert("RGB")
w, h = im.size
# fractions of the original, tuned per plate by eye then checked
im = im.crop((int(0.04*w), int(0.02*h), int(0.97*w), int(0.98*h)))
im.thumbnail((1600, 1600), Image.LANCZOS)
im.save("bird.jpg", "JPEG", quality=82, optimize=True, progressive=True)
```

That lands each plate around 170–260 KB, which is what gets committed to
`nixos/hosts/<host>/bird.jpg`. Crop fractions differ per plate — check the
result rather than reusing another host's numbers. macOS `sips` is not a
substitute here: it only crops from the centre, so it cannot trim an uneven
margin.

## Adding a host

1. Drop the prepared plate at `nixos/hosts/<host>/bird.jpg`.
2. Add `./nixos/modules/holding-page.nix` to that host's module list in
   `flake.nix`.
3. Put the hostname on a certificate the host already has, via
   `extraDomainNames`. Falcon is the exception and carries its own, having no
   name in the int zone — see `nixos/hosts/falcon/web.nix`.
4. Enable it:

```nix
alcachofa.holdingPage = {
  enable = true;
  domains = [ "heron.int.alcachofa.faith" ];
  useACMEHost = "<the cert from step 3>";
  image = ./bird.jpg;
  plate = "Heron, Ardea cinerea";
  alt = "A heron standing in shallow water.";
  credit = "Heron, <i>Ardea cinerea</i>. Archibald Thorburn, from Lilford's <i>Coloured Figures of the Birds of the British Islands</i> (1885-97). Public domain, via Wikimedia Commons.";
};
```

DNS needs no work if the host already has a dnsmasq reservation with a
`domain` set — the int name resolves from that.

Issuance is DNS-01 throughout, so a certificate works for a name pointing at a
LAN or tailnet address that no ACME server could ever reach over HTTP.
