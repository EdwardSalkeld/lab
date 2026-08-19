{
  description = "Home lab NixOS configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    # The Codex CLI moves fast; the pinned 25.11 channel only has an old
    # release that the current backend rejects (gpt-5.4 needs a newer CLI), so
    # the chatting worker takes Codex from unstable.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    octopus-dl = {
      url = "github:EdwardSalkeld/octopus-dl";
      flake = false;
    };
    linear-export = {
      url = "github:EdwardSalkeld/linear-export";
      flake = false;
    };
    exercise-tracker = {
      url = "github:EdwardSalkeld/exercise-tracker";
      flake = false;
    };
    # chatting tracks its default branch; bump with `nix flake update chatting`.
    chatting = {
      url = "github:EdwardSalkeld/chatting";
      flake = false;
    };
    # bbmb is release-pinned; change the ref to move it.
    bbmb = {
      url = "github:EdwardSalkeld/bbmb/v7";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, sops-nix, octopus-dl, linear-export, exercise-tracker, chatting, bbmb, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      pkgsUnstable = import nixpkgs-unstable { inherit system; };
      chattingSrc = chatting;
      bbmbSrc = bbmb;
      chattingHandler = pkgs.buildGoModule {
        pname = "chatting-handler";
        version = "2026-07-27";
        src = chattingSrc;
        modRoot = "go/handler";
        vendorHash = "sha256-vw4CijMxBtBDQLDNefq5AfQa1SoXbKHc3BHxYdwXGoM=";
        subPackages = [ "cmd/chatting-handler" ];
        doCheck = false;
      };
      chattingWorkerPython = pkgs.python3.withPackages (ps: [ ps.croniter ]);
      chattingWorker = pkgs.writeShellApplication {
        name = "chatting-worker";
        runtimeInputs = [ chattingWorkerPython ];
        text = ''
          export PYTHONPATH=${chattingSrc}''${PYTHONPATH:+:$PYTHONPATH}
          exec python -m app.main_worker "$@"
        '';
      };
      bbmbServer = pkgs.buildGo126Module {
        pname = "bbmb-server";
        version = "v7";
        src = bbmbSrc;
        modRoot = "server";
        vendorHash = null;
        subPackages = [ "." ];
        doCheck = false;
        # Upstream bbmb v7 now requires Go 1.26.
        postInstall = ''
          mv "$out/bin/server" "$out/bin/bbmb-server"
        '';
      };
      chattingRuntime = pkgs.symlinkJoin {
        name = "chatting-runtime";
        paths = [
          bbmbServer
          chattingHandler
          chattingWorker
        ];
      };
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
        # Tests run in CI; skip them here so the build does not compile the
        # CGO sqlite test driver (a ~250k-line C file, slow and disk-hungry)
        # that the binary itself never uses.
        doCheck = false;
      };
      linearExport = pkgs.buildGoModule {
        pname = "linear-export";
        version = "0.1.0";
        src = linear-export;
        vendorHash = null;
        subPackages = [ "." ];
        # Tests run in CI; skip them here so the build does not compile the
        # CGO sqlite test driver (a ~250k-line C file, slow and disk-hungry)
        # that the binary itself never uses.
        doCheck = false;
      };
      exerciseTracker = pkgs.buildGoModule {
        pname = "exercise-tracker";
        version = "0.1.0";
        src = exercise-tracker;
        vendorHash = null;
        subPackages = [ "cmd/exercise-tracker" ];
        # Tests run in CI; the nix build only needs the binary.
        doCheck = false;
        # The db-setup unit applies these migrations at activation, so they must
        # ship in the package output, not just the source tree.
        postInstall = ''
          install -Dm644 sql/migrations/*.sql -t $out/share/exercise-tracker/sql/migrations/
        '';
      };
    in
    {
      packages.${system} = {
        bbmb-server = bbmbServer;
        bitwarden-mirror = bitwardenMirror;
        chatting-handler = chattingHandler;
        chatting-runtime = chattingRuntime;
        chatting-worker = chattingWorker;
        octopus-dl = octopusDl;
        linear-export = linearExport;
        exercise-tracker = exerciseTracker;
        default = bitwardenMirror;
      };

      checks.${system} =
        let
          partridgeConfig = self.nixosConfigurations.partridge.config;
          partridgeGrafanaTemplates = builtins.toFile "partridge-grafana-alerting-templates.json" (
            builtins.toJSON partridgeConfig.services.grafana.provision.alerting.templates.settings
          );
          partridgeGrafanaContactPoints = builtins.toFile "partridge-grafana-alerting-contact-points.json" (
            builtins.toJSON partridgeConfig.services.grafana.provision.alerting.contactPoints.settings
          );
        in
        {
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

          grafana-alerting-lint = pkgs.runCommand "grafana-alerting-lint"
            {
              nativeBuildInputs = [
                pkgs.go
                pkgs.grafana
              ];
              src = ./tools/grafana-alerting-lint;
              templatesJson = partridgeGrafanaTemplates;
              contactPointsJson = partridgeGrafanaContactPoints;
            }
            ''
              cp -R "$src" source
              chmod -R u+w source
              cd source
              export HOME="$TMPDIR"
              export GOCACHE="$TMPDIR/go-cache"
              go run . "$templatesJson" "$contactPointsJson"

              mkdir -p grafana-smoke/provisioning/alerting
              mkdir -p grafana-smoke/provisioning/dashboards
              mkdir -p grafana-smoke/provisioning/datasources
              mkdir -p grafana-smoke/provisioning/plugins
              mkdir -p grafana-smoke/data
              mkdir -p grafana-smoke/logs
              mkdir -p grafana-smoke/plugins
              cp "$templatesJson" grafana-smoke/provisioning/alerting/templates.json
              cp "$contactPointsJson" grafana-smoke/provisioning/alerting/contactpoints.json

              export GF_PATHS_PROVISIONING="$PWD/grafana-smoke/provisioning"
              export GF_PATHS_DATA="$PWD/grafana-smoke/data"
              export GF_PATHS_LOGS="$PWD/grafana-smoke/logs"
              export GF_PATHS_PLUGINS="$PWD/grafana-smoke/plugins"
              export GRAFANA_TELEGRAM_BOT_TOKEN=dummy

              set +e
              ${pkgs.coreutils}/bin/timeout 20s \
                ${pkgs.grafana}/bin/grafana server \
                --homepath ${pkgs.grafana}/share/grafana \
                --config ${pkgs.grafana}/share/grafana/conf/defaults.ini \
                > grafana-smoke/stdout.log 2> grafana-smoke/stderr.log
              status=$?
              set -e

              if [ "$status" -ne 124 ]; then
                cat grafana-smoke/stdout.log
                cat grafana-smoke/stderr.log
                echo "Grafana alerting smoke test failed with exit status $status" >&2
                exit 1
              fi

              touch "$out"
            '';

          partridge = partridgeConfig.system.build.toplevel;
          blink = self.nixosConfigurations.blink.config.system.build.toplevel;
          magpie = self.nixosConfigurations.magpie.config.system.build.toplevel;
        };

      nixosConfigurations = {
        blink = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            ./nixos/hosts/blink/configuration.nix
          ];
        };

        partridge = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            bitwardenMirrorPackage = bitwardenMirror;
            octopusDlPackage = octopusDl;
            linearExportPackage = linearExport;
            exerciseTrackerPackage = exerciseTracker;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./nixos/modules/proxmox-vm-base.nix
            ./nixos/modules/remote-deploy.nix
            ./nixos/hosts/partridge/configuration.nix
          ];
        };

        magpie = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            chattingRuntimePackage = chattingRuntime;
            codexPackage = pkgsUnstable.codex;
            goosePackage = pkgsUnstable.goose-cli;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./nixos/modules/proxmox-vm-base.nix
            ./nixos/modules/remote-deploy.nix
            ./nixos/hosts/magpie/configuration.nix
          ];
        };
      };
    };
}
