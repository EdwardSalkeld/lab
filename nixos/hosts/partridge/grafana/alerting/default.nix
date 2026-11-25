{ lib }:

let
  common = import ./common.nix;
in
{
  rules.settings = import ./rules { inherit lib; };
  contactPoints.settings = import ./contact-points.nix { inherit common; };
  templates.settings = import ./templates.nix;
  policies.settings = import ./policies.nix { inherit common; };
}
