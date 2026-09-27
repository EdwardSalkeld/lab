# Pinned ahead of nixpkgs, which still ships 0.0.11 — too old for OPNsense 26.1
# (the gateways API changed `priority` to a number and 0.0.11 fails to parse it).
# Needs Go 1.27, hence buildGo127Module. Drop this once nixpkgs catches up.
{
  buildGo127Module,
  fetchFromGitHub,
}:
buildGo127Module rec {
  pname = "opnsense-exporter";
  version = "0.0.17";

  src = fetchFromGitHub {
    owner = "AthennaMind";
    repo = "opnsense-exporter";
    rev = "v${version}";
    hash = "sha256-3J33H2k8W5K02YCqzRp7vLJoy26Qpcf60lvhKifwAqw=";
  };

  # The upstream repo vendors its dependencies.
  vendorHash = null;

  ldflags = [
    "-s"
    "-w"
  ];

  meta.mainProgram = "opnsense-exporter";
}
