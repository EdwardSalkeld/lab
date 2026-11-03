{ pkgs, ... }:

{
  # The standard interactive Python for every Lab-managed host.
  environment.systemPackages = [ pkgs.python314 ];
}
