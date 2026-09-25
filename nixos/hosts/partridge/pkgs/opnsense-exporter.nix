# Pinned ahead of nixpkgs, which still ships 0.0.11 — too old for OPNsense 26.1
# (the gateways API changed `priority` to a number and 0.0.11 fails to parse it).
# Needs Go 1.26, hence buildGo126Module. Drop this once nixpkgs catches up.
{
  buildGo126Module,
  fetchFromGitHub,
}:
buildGo126Module rec {
  pname = "opnsense-exporter";
  version = "0.0.16";

  src = fetchFromGitHub {
    owner = "AthennaMind";
    repo = "opnsense-exporter";
    rev = "v${version}";
    hash = "sha256-oAQm2bxcDQfqTdtVtot1Dk2MkFqG5wVxeERie5DRoOQ=";
  };

  # The upstream repo vendors its dependencies.
  vendorHash = null;

  ldflags = [
    "-s"
    "-w"
  ];

  meta.mainProgram = "opnsense-exporter";
}
