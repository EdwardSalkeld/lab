{ buildGoModule }:

buildGoModule {
  pname = "bitwarden-mirror";
  version = "0.1.0";
  src = ../../tools/bitwarden-mirror;
  vendorHash = null;
  subPackages = [ "cmd/bitwarden-mirror" ];
}
