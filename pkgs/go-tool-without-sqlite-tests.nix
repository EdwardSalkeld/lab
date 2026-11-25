# Builds an upstream Go tool whose tests need the CGO sqlite driver.
{
  buildGoModule,
  pname,
  src,
}:

buildGoModule {
  inherit pname src;
  version = "0.1.0";
  vendorHash = null;
  subPackages = [ "." ];
  # Tests run in CI; skip them here so the build does not compile the
  # CGO sqlite test driver (a ~250k-line C file, slow and disk-hungry)
  # that the binary itself never uses.
  doCheck = false;
}
