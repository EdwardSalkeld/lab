{
  description = "Home lab NixOS configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Keep the chatting worker's CLI current with the model selected by
    # chatting. Codex 0.156.1 rejected gpt-6.1-sol; 0.161.0 was verified on
    # magpie with the worker's ChatGPT login.
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
    # chatting is pinned to a release tag and built by its own flake; change
    # the tag and run `nix flake update chatting` to move it. Its nixpkgs is
    # deliberately not made to follow ours, so the packages built here are the
    # ones Chatting's CI built and tested for that release.
    chatting.url = "github:EdwardSalkeld/chatting/v0.1.775";
    media-collection-manager = {
      url = "github:brokensbone/media-collection-manager";
    };
    # bbmb is release-pinned; change the ref to move it.
    bbmb = {
      url = "github:EdwardSalkeld/bbmb/v10";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      sops-nix,
      octopus-dl,
      linear-export,
      exercise-tracker,
      chatting,
      media-collection-manager,
      bbmb,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ self.overlays.default ];
      };
      pkgsUnstable = import nixpkgs-unstable { inherit system; };
      chattingSrc = chatting;
      mediaCollectionManagerPackages = media-collection-manager.packages.${system};

      mkHost =
        name:
        {
          specialArgs ? { },
          labBase ? true,
          proxmoxGuest ? true,
        }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            tailscalePackage = pkgsUnstable.tailscale;
          }
          // specialArgs;
          modules = [
            sops-nix.nixosModules.sops
            ./nixos/modules/holding-page.nix
            ./nixos/modules/journal-logging.nix
          ]
          ++ nixpkgs.lib.optional labBase ./nixos/modules/lab-base.nix
          ++ nixpkgs.lib.optional proxmoxGuest ./nixos/modules/proxmox-guest.nix
          ++ [
            ./nixos/modules/remote-deploy.nix
            ./nixos/modules/shell-scripts.nix
            ./nixos/hosts/${name}/configuration.nix
          ];
        };
    in
    {
      overlays.default = final: _prev: {
        bbmb-server = final.callPackage ./pkgs/bbmb-server { src = bbmb; };
        bitwarden-mirror = final.callPackage ./pkgs/bitwarden-mirror { };
        chatting-runtime = final.callPackage ./pkgs/chatting-runtime {
          chattingPackages = chatting.packages.${final.stdenv.hostPlatform.system};
        };
        exercise-tracker = final.callPackage ./pkgs/exercise-tracker { src = exercise-tracker; };
        linear-export = final.callPackage ./pkgs/go-tool-without-sqlite-tests.nix {
          pname = "linear-export";
          src = linear-export;
        };
        octopus-dl = final.callPackage ./pkgs/go-tool-without-sqlite-tests.nix {
          pname = "octopus-dl";
          src = octopus-dl;
        };
      };

      packages.${system} = {
        inherit (pkgs)
          bbmb-server
          bitwarden-mirror
          chatting-runtime
          exercise-tracker
          linear-export
          octopus-dl
          ;
        inherit (chatting.packages.${system}) chatting-handler chatting-worker;
        default = pkgs.bitwarden-mirror;
      };

      checks.${system} =
        let
          partridgeConfig = self.nixosConfigurations.partridge.config;
          partridgeGrafanaProvision = partridgeConfig.services.grafana.provision;
          partridgeGrafanaJson =
            name: value: builtins.toFile "partridge-grafana-${name}.json" (builtins.toJSON value);
          partridgeGrafanaTemplates = partridgeGrafanaJson "alerting-templates" partridgeGrafanaProvision.alerting.templates.settings;
          partridgeGrafanaContactPoints = partridgeGrafanaJson "alerting-contact-points" partridgeGrafanaProvision.alerting.contactPoints.settings;
          partridgeGrafanaRules = partridgeGrafanaJson "alerting-rules" partridgeGrafanaProvision.alerting.rules.settings;
          partridgeGrafanaPolicies = partridgeGrafanaJson "alerting-policies" partridgeGrafanaProvision.alerting.policies.settings;
          partridgeGrafanaDatasources = partridgeGrafanaJson "datasources" partridgeGrafanaProvision.datasources.settings;
          partridgeGrafanaDashboards = partridgeGrafanaJson "dashboards" partridgeGrafanaProvision.dashboards.settings;
        in
        {
          lab-python = pkgs.runCommand "lab-python-check" { } (
            pkgs.lib.concatMapStringsSep "\n" (host: ''
              ${self.nixosConfigurations.${host}.config.system.path}/bin/python3 -c '
              import sys
              assert sys.version_info[:2] == (3, 14), sys.version
              '
            '') (builtins.attrNames self.nixosConfigurations)
            + ''
              # Exercise the reply helper through Magpie's default profile too.
              export PYTHONPATH=${chattingSrc}
              export PYTHONDONTWRITEBYTECODE=1
              ${self.nixosConfigurations.magpie.config.system.path}/bin/python3 -c 'import app.main_reply'
              touch "$out"
            ''
          );

          network-arrivals =
            pkgs.runCommand "network-arrivals-check"
              {
                nativeBuildInputs = [
                  (pkgs.python3.withPackages (p: [ p.psycopg2 ]))
                  pkgs.postgresql
                ];
              }
              ''
                export HOME="$TMPDIR"
                export PYTHONDONTWRITEBYTECODE=1
                initdb -D "$TMPDIR/pg" --no-locale -A trust >/dev/null
                trap 'pg_ctl -D "$TMPDIR/pg" -m immediate stop >/dev/null' EXIT
                pg_ctl -D "$TMPDIR/pg" -o "-k $TMPDIR -c listen_addresses=" -w start >/dev/null
                export TEST_DATABASE="dbname=postgres host=$TMPDIR"
                python3 -m unittest discover -s ${./tools/network-arrivals} -v
                touch "$out"
              '';

          router-syslog =
            pkgs.runCommand "router-syslog-check"
              {
                nativeBuildInputs = [ pkgs.python314 ];
                routerConfig =
                  pkgs.writeText "router-syslog.alloy"
                    partridgeConfig.environment.etc."alloy/router-syslog.alloy".text;
              }
              ''
                python3 ${./scripts/check-router-syslog.py} \
                  --alloy ${partridgeConfig.services.alloy.package}/bin/alloy \
                  --config "$routerConfig"
                touch "$out"
              '';

          nix-shellcheck = import ./nixos/checks/shellcheck.nix {
            inherit (pkgs) lib;
            inherit pkgs;
            inherit (self) nixosConfigurations;
            repoRoot = self;
          };

          # Validates each host's /etc/alloy as Alloy loads it, as one directory,
          # so references between files (router-syslog writing to the journal
          # config's loki.write) are checked too. alloy fmt is left out: it
          # indents with tabs and the Nix-rendered configs use spaces.
          alloy-config = pkgs.runCommand "alloy-config-check" { } (
            pkgs.lib.concatMapStrings (
              host:
              let
                config = self.nixosConfigurations.${host}.config;
                files = pkgs.lib.filterAttrs (name: _: pkgs.lib.hasPrefix "alloy/" name) config.environment.etc;
              in
              pkgs.lib.optionalString config.services.alloy.enable ''
                mkdir "$TMPDIR/${host}"
                ${pkgs.lib.concatStrings (
                  pkgs.lib.mapAttrsToList (name: file: ''
                    cp ${file.source} "$TMPDIR/${host}/${pkgs.lib.removePrefix "alloy/" name}"
                  '') files
                )}
                ${config.services.alloy.package}/bin/alloy validate "$TMPDIR/${host}"
              ''
            ) (builtins.attrNames self.nixosConfigurations)
            + ''
              # install.sh downloads the same Alloy release and sets HOSTNAME.
              HOSTNAME=sol ${pkgs.grafana-alloy}/bin/alloy validate ${./proxmox/journal-to-loki/config.alloy}
              touch "$out"
            ''
          );

          bitwarden-mirror-go-tests =
            pkgs.runCommand "bitwarden-mirror-go-tests"
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

          grafana-alerting-lint =
            pkgs.runCommand "grafana-alerting-lint"
              {
                nativeBuildInputs = [
                  pkgs.go
                  pkgs.curl
                  pkgs.jq
                ];
                src = ./tools/grafana-alerting-lint;
                templatesJson = partridgeGrafanaTemplates;
                contactPointsJson = partridgeGrafanaContactPoints;
                rulesJson = partridgeGrafanaRules;
                policiesJson = partridgeGrafanaPolicies;
                datasourcesJson = partridgeGrafanaDatasources;
                dashboardsJson = partridgeGrafanaDashboards;
              }
              ''
                cp -R "$src" source
                chmod -R u+w source
                cd source
                export HOME="$TMPDIR"
                export GOCACHE="$TMPDIR/go-cache"
                go test ./...
                go run . \
                  -templates "$templatesJson" \
                  -contact-points "$contactPointsJson" \
                  -rules "$rulesJson" \
                  -datasources "$datasourcesJson" \
                  -dashboards "$dashboardsJson"

                provisioning="$TMPDIR/provisioning"
                mkdir -p "$provisioning"/{alerting,dashboards,datasources,plugins}
                cp "$templatesJson" "$provisioning/alerting/templates.yaml"
                cp "$contactPointsJson" "$provisioning/alerting/contactpoints.yaml"
                cp "$rulesJson" "$provisioning/alerting/rules.yaml"
                cp "$policiesJson" "$provisioning/alerting/policies.yaml"
                cp "$datasourcesJson" "$provisioning/datasources/datasources.yaml"
                cp "$dashboardsJson" "$provisioning/dashboards/dashboards.yaml"

                bash ./smoke.sh ${partridgeConfig.services.grafana.package} "$provisioning" "$TMPDIR/grafana-smoke"

                touch "$out"
              '';
        };

      nixosConfigurations = {
        partridge = mkHost "partridge" {
          specialArgs = {
            bitwardenMirrorPackage = pkgs.bitwarden-mirror;
            octopusDlPackage = pkgs.octopus-dl;
            linearExportPackage = pkgs.linear-export;
            exerciseTrackerPackage = pkgs.exercise-tracker;
            grafanaPackage = pkgsUnstable.grafana;
          };
        };

        magpie = mkHost "magpie" {
          specialArgs = {
            chattingRuntimePackage = pkgs.chatting-runtime;
            codexPackage = pkgsUnstable.codex;
          };
        };

        kite = mkHost "kite" {
          specialArgs = { inherit mediaCollectionManagerPackages; };
        };

        # Falcon is a Hetzner Cloud VM, not a Proxmox guest. It also skips
        # lab-base for now, because its own copy of those settings has diverged.
        falcon = mkHost "falcon" {
          labBase = false;
          proxmoxGuest = false;
        };
      };
    };
}
