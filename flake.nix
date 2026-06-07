{
  description = "Home lab NixOS configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, sops-nix, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      bitwardenMirror = pkgs.buildGoModule {
        pname = "bitwarden-mirror";
        version = "0.1.0";
        src = ./tools/bitwarden-mirror;
        vendorHash = null;
        subPackages = [ "cmd/bitwarden-mirror" ];
      };
    in
    {
      packages.${system} = {
        bitwarden-mirror = bitwardenMirror;
        magpie-image = self.nixosConfigurations.magpie.config.system.build.images.qemu-efi;
        default = bitwardenMirror;
      };

      checks.${system} = {
        bitwarden-mirror-go-tests = pkgs.runCommand "bitwarden-mirror-go-tests"
          {
            nativeBuildInputs = [ pkgs.go ];
            src = ./tools/bitwarden-mirror;
          }
          ''
            cp -R "$src" source
            chmod -R u+w source
            cd source
            export HOME="$TMPDIR"
            export GOCACHE="$TMPDIR/go-cache"
            go test ./...
            touch "$out"
          '';

        partridge = self.nixosConfigurations.partridge.config.system.build.toplevel;
        magpie = self.nixosConfigurations.magpie.config.system.build.toplevel;
      };

      nixosConfigurations = {
        partridge = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            bitwardenMirrorPackage = bitwardenMirror;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./nixos/modules/proxmox-vm-base.nix
            ./nixos/hosts/partridge/configuration.nix
          ];
        };

        magpie = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            ./nixos/modules/proxmox-vm-base.nix
            ./nixos/modules/disposable-dev-machine.nix
            ./nixos/hosts/magpie/configuration.nix
          ];
        };
      };
    };
}
