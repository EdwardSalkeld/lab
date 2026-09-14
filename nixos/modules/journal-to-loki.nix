{ config, lib, ... }:

let
  cfg = config.alcachofa.journalToLoki;
in
{
  options.alcachofa.journalToLoki = {
    enable = lib.mkEnableOption "shipping the complete systemd journal to Loki";

    endpoint = lib.mkOption {
      type = lib.types.str;
      default = "https://loki.int.alcachofa.faith/loki/api/v1/push";
      description = "Loki push endpoint for journal entries.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.alloy = {
      enable = true;
      extraFlags = [
        "--server.http.listen-addr=127.0.0.1:9080"
        "--server.http.ui-path-prefix=/"
        "--disable-reporting"
      ];
    };

    environment.etc."alloy/journal-to-loki.alloy".text = ''
      loki.relabel "systemd_journal" {
        forward_to = []

        rule {
          source_labels = ["__journal__systemd_unit"]
          target_label  = "systemd_unit"
        }

        rule {
          source_labels = ["__journal_priority_keyword"]
          target_label  = "level"
        }
      }

      loki.source.journal "systemd_journal" {
        forward_to    = [loki.write.default.receiver]
        relabel_rules = loki.relabel.systemd_journal.rules
        max_age       = "24h"
        labels = {
          host   = "${config.networking.hostName}",
          source = "journal",
        }
      }

      loki.write "default" {
        endpoint {
          url = "${cfg.endpoint}"
        }
      }
    '';
  };
}
