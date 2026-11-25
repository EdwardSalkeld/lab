{ buildGo127Module, src }:

buildGo127Module {
  pname = "bbmb-server";
  version = "v10";
  inherit src;
  modRoot = "server";
  vendorHash = null;
  subPackages = [ "." ];
  doCheck = false;
  # Upstream bbmb requires Go 1.27.
  postInstall = ''
    mv "$out/bin/server" "$out/bin/bbmb-server"
  '';
}
