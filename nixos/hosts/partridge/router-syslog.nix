{ config, ... }:

{
  # DD-WRT's BusyBox syslogd accepts HOST:PORT. A high port lets Alloy keep
  # its existing privileges. Both machines are on the wired side of the bridge.
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -s 10.4.1.2 -d 10.4.1.30 -p udp --dport 1514 -j nixos-fw-accept
  '';

  assertions = [
    {
      assertion = config.alcachofa.journalToLoki.enable;
      message = "Router syslog requires the shared Alloy Loki writer.";
    }
  ];

  systemd.services.alloy.restartTriggers = [
    config.environment.etc."alloy/router-syslog.alloy".source
  ];
  alcachofa.remoteDeploy.postSwitchHealthchecks = [ "alloy.service" ];

  environment.etc."alloy/router-syslog.alloy".text = ''
    loki.relabel "archer_c9_metadata" {
      forward_to = []

      rule {
        source_labels = ["__syslog_connection_ip_address"]
        target_label  = "sender_ip"
      }

      rule {
        source_labels = ["__syslog_message_severity"]
        target_label  = "level"
      }

      rule {
        source_labels = ["__syslog_message_facility"]
        target_label  = "facility"
      }

      rule {
        source_labels = ["__syslog_message_app_name"]
        target_label  = "program"
      }
    }

    loki.relabel "archer_c9" {
      rule {
        source_labels = ["sender_ip"]
        regex         = "10[.]4[.]1[.]2"
        action        = "keep"
      }

      forward_to = [loki.write.default.receiver]
    }

    loki.source.syslog "archer_c9" {
      listener {
        address                = "0.0.0.0:1514"
        protocol               = "udp"
        syslog_format          = "rfc3164"
        use_incoming_timestamp = false
        labels = {
          host   = "archer-c9",
          source = "syslog",
        }
      }

      relabel_rules = loki.relabel.archer_c9_metadata.rules
      forward_to    = [loki.relabel.archer_c9.receiver]
    }
  '';
}
