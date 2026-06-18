{
  description = "Home lab NixOS configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    octopus-dl = {
      url = "github:EdwardSalkeld/octopus-dl";
      flake = false;
    };
    exercise-tracker = {
      url = "github:EdwardSalkeld/exercise-tracker";
      flake = false;
    };
    linear-export = {
      url = "github:EdwardSalkeld/linear-export";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, sops-nix, octopus-dl, exercise-tracker, linear-export, ... }:
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
      octopusDl = pkgs.buildGoModule {
        pname = "octopus-dl";
        version = "0.1.0";
        src = octopus-dl;
        vendorHash = null;
        subPackages = [ "." ];
      };
      exerciseTracker = pkgs.buildGoModule {
        pname = "exercise-tracker";
        version = "0.1.0";
        src = exercise-tracker;
        vendorHash = "sha256-4k3CIJyI20N9YoF82BdD4nA29HL40KPYzsP7CqGa28A=";
        subPackages = [ "." ];
      };
      linearExport = pkgs.buildGoModule {
        pname = "linear-export";
        version = "0.1.0";
        src = linear-export;
        vendorHash = null;
        subPackages = [ "." ];
      };
    in
    {
      packages.${system} = {
        bitwarden-mirror = bitwardenMirror;
        octopus-dl = octopusDl;
        exercise-tracker = exerciseTracker;
        linear-export = linearExport;
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
      };

      nixosConfigurations = {
        partridge = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            bitwardenMirrorPackage = bitwardenMirror;
            octopusDlPackage = octopusDl;
            exerciseTrackerPackage = exerciseTracker;
            linearExportPackage = linearExport;
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
