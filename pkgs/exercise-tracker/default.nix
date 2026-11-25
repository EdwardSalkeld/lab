{ buildGoModule, src }:

buildGoModule {
  pname = "exercise-tracker";
  version = "0.1.0";
  inherit src;
  vendorHash = null;
  subPackages = [ "cmd/exercise-tracker" ];
  # Tests run in CI; the nix build only needs the binary.
  doCheck = false;
  # The db-setup unit applies these migrations at activation, so they must
  # ship in the package output, not just the source tree.
  postInstall = ''
    install -Dm644 sql/migrations/*.sql -t $out/share/exercise-tracker/sql/migrations/
  '';
}
