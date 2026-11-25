{ lib, ... }:
{
  # Nothing on the host reads this; it exists so the flake's shellcheck check
  # can reach scripts that are only bound in a module's `let`.
  options.alcachofa.shellScripts = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [ ];
    internal = true;
    description = "Scripts this repo writes with writeShellScript, for the flake's shellcheck check.";
  };
}
