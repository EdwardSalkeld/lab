{
  config,
  pkgs,
  lib,
  grafanaPackage,
  ...
}:

let
  grafanaDomain = "grafana.alcachofa.faith";
  grafanaPort = 3001;
  alertingCommon = import ./grafana/alerting/common.nix;
  inherit (alertingCommon) alertsTelegramChatId;
  grafanaFailureNotify = pkgs.writeShellScript "grafana-failure-notify" ''
    set -euo pipefail

    unit="''${1:?usage: grafana-failure-notify <systemd-unit>}"
    state_dir=/var/lib/grafana-failure-notify
    cooldown_seconds=900
    exec 9>"$state_dir/lock"
    ${pkgs.util-linux}/bin/flock 9

    now_epoch="$(${pkgs.coreutils}/bin/date +%s)"
    last_notified=0
    if [ -r "$state_dir/last-notified" ]; then
      read -r last_notified < "$state_dir/last-notified" || true
    fi
    if ! [[ "$last_notified" =~ ^[0-9]+$ ]]; then
      last_notified=0
    fi
    if (( now_epoch - last_notified < cooldown_seconds )); then
      exit 0
    fi

    host="$("/run/current-system/sw/bin/hostname" -s)"
    now="$("/run/current-system/sw/bin/date" -u +"%Y-%m-%d %H:%M:%S UTC")"
    result="$("/run/current-system/sw/bin/systemctl" show "$unit" --property=Result --value 2>/dev/null || true)"
    active_state="$("/run/current-system/sw/bin/systemctl" show "$unit" --property=ActiveState --value 2>/dev/null || true)"
    sub_state="$("/run/current-system/sw/bin/systemctl" show "$unit" --property=SubState --value 2>/dev/null || true)"
    text="Grafana failed on $host at $now. unit=$unit active=$active_state sub=$sub_state result=''${result:-unknown}. Check journalctl -u $unit -n 80 --no-pager."

    ${pkgs.curl}/bin/curl \
      --fail \
      --silent \
      --show-error \
      --data-urlencode "chat_id=${alertsTelegramChatId}" \
      --data-urlencode "text=$text" \
      --data-urlencode "disable_web_page_preview=true" \
      "https://api.telegram.org/bot''${GRAFANA_TELEGRAM_BOT_TOKEN}/sendMessage"

    printf '%s\n' "$now_epoch" > "$state_dir/last-notified"
  '';
  # Grafana 13 can crash-loop during file-based alert provisioning when a
  # unified-storage folder retains UI user provenance. Normalize it before
  # startup until https://github.com/grafana/grafana/issues/128708 is fixed.
  grafanaFolderProvenanceRepair = pkgs.writeShellScript "grafana-folder-provenance-repair" ''
    set -euo pipefail

    exec ${config.services.postgresql.package}/bin/psql \
      --dbname=grafana \
      --set=ON_ERROR_STOP=1 \
      --quiet \
      --command="
        UPDATE resource
        SET value = jsonb_set(
          jsonb_set(
            value::jsonb,
            '{metadata,annotations,grafana.app/createdBy}',
            to_jsonb('provisioning:'::text)
          ),
          '{metadata,annotations,grafana.app/updatedBy}',
          to_jsonb('provisioning:'::text)
        )::text
        WHERE \"group\" = 'folder.grafana.app'
          AND (
            value::jsonb #>> '{metadata,annotations,grafana.app/createdBy}' LIKE 'user:%'
            OR value::jsonb #>> '{metadata,annotations,grafana.app/updatedBy}' LIKE 'user:%'
          );
      "
  '';
in
{
  alcachofa.partridge.reverseProxy.routes.${grafanaDomain}.port = grafanaPort;
  alcachofa.remoteDeploy.postSwitchHealthchecks = [ "grafana.service" ];
  alcachofa.remoteDeploy.postSwitchHttpChecks = [
    "http://127.0.0.1:${toString grafanaPort}/api/health"
  ];

  sops.secrets."grafana/smtp_password" = {
    sopsFile = ./secrets/grafana-smtp.yaml;
    key = "smtp_password";
    owner = "grafana";
    group = "grafana";
    mode = "0400";
  };
  sops.secrets."grafana/telegram_bot_token" = {
    sopsFile = ./secrets/grafana-telegram.yaml;
    key = "telegram_bot_token";
    owner = "grafana";
    group = "grafana";
    mode = "0400";
  };
  sops.secrets."grafana/secret_key" = {
    sopsFile = ./secrets/grafana-security.yaml;
    key = "secret_key";
    owner = "grafana";
    group = "grafana";
    mode = "0400";
    # The secret's path never changes, so a rotated key would otherwise sit on
    # disk while Grafana kept using the old one from memory until something
    # restarted it.
    restartUnits = [ "grafana.service" ];
  };
  sops.templates."grafana-alerting.env" = {
    owner = "grafana";
    group = "grafana";
    mode = "0400";
    content = ''
      GRAFANA_SMTP_PASSWORD=${config.sops.placeholder."grafana/smtp_password"}
      GRAFANA_TELEGRAM_BOT_TOKEN=${config.sops.placeholder."grafana/telegram_bot_token"}
    '';
    # Both secrets reach Grafana only through this file, and its path does not
    # change when the values do, so rotating either would otherwise leave
    # Grafana running on the old credentials.
    restartUnits = [ "grafana.service" ];
  };

  systemd.services.grafana.serviceConfig.EnvironmentFile =
    config.sops.templates."grafana-alerting.env".path;
  systemd.services.grafana-folder-provenance-repair = {
    description = "Normalize Grafana unified-folder provenance before startup";
    before = [ "grafana.service" ];
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      Group = "postgres";
      ExecStart = grafanaFolderProvenanceRepair;
    };
  };
  systemd.services.grafana.requires = [ "grafana-folder-provenance-repair.service" ];
  systemd.services.grafana.after = [ "grafana-folder-provenance-repair.service" ];
  systemd.services.grafana.unitConfig = {
    StartLimitIntervalSec = "5min";
    StartLimitBurst = 3;
  };
  systemd.services.grafana.serviceConfig.RestartSec = "15s";
  systemd.services.grafana.onFailure = [ "grafana-failure-notify.service" ];
  systemd.services.grafana-failure-notify = {
    description = "Notify Telegram when Grafana fails (15 minute cooldown)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "grafana-failure-notify";
      StateDirectoryMode = "0700";
      EnvironmentFile = config.sops.templates."grafana-alerting.env".path;
      ExecStart = "${grafanaFailureNotify} grafana.service";
    };
  };

  services.postgresql = {
    ensureDatabases = [ "grafana" ];
    ensureUsers = [
      {
        name = "grafana";
        ensureDBOwnership = true;
      }
    ];
  };

  services.grafana = {
    enable = true;
    package = grafanaPackage;

    settings = {
      server = {
        domain = grafanaDomain;
        http_addr = "127.0.0.1";
        http_port = grafanaPort;
        root_url = "https://${grafanaDomain}/";
      };

      security.secret_key = "$__file{${config.sops.secrets."grafana/secret_key".path}}";

      database = {
        type = "postgres";
        host = "/run/postgresql";
        name = "grafana";
        user = "grafana";
      };

      users = {
        allow_sign_up = false;
        allow_org_create = false;
      };

      smtp = {
        enabled = true;
        host = "smtp.fastmail.com:587";
        user = "edsalkeld@fastmail.com";
        password = "$__env{GRAFANA_SMTP_PASSWORD}";
        from_address = "edsalkeld@fastmail.com";
        from_name = "Grafana";
        startTLS_policy = "MandatoryStartTLS";
      };
    };

    provision.datasources.settings = {
      apiVersion = 1;
      datasources = [
        {
          name = "prometheus";
          uid = "fdp9rmnopl3wgf";
          type = "prometheus";
          access = "proxy";
          url = "http://127.0.0.1:9090";
          isDefault = true;
          editable = true;
        }
        {
          name = "loki";
          uid = "ce6j6e2q9rapsa";
          type = "loki";
          access = "proxy";
          url = "http://127.0.0.1:3100";
          editable = true;
        }
        {
          name = "scheduler-postgres";
          uid = "scheduler-postgres";
          type = "postgres";
          access = "proxy";
          url = "/run/postgresql";
          user = "grafana";
          jsonData = {
            database = "scheduler";
            sslmode = "disable";
          };
          editable = true;
        }
        {
          name = "network-inventory-postgres";
          uid = "network-inventory-postgres";
          type = "postgres";
          access = "proxy";
          url = "/run/postgresql";
          user = "grafana";
          jsonData = {
            database = "network_inventory";
            sslmode = "disable";
          };
          editable = false;
        }
        {
          name = "exercise-tracker-postgres";
          uid = "exercise-tracker-postgres";
          type = "postgres";
          access = "proxy";
          url = "/run/postgresql";
          user = "grafana";
          jsonData = {
            database = "exercise_tracker";
            sslmode = "disable";
          };
          editable = true;
        }
      ];
    };

    provision.dashboards.settings = {
      apiVersion = 1;
      providers = [
        {
          name = "ops";
          folder = "Ops";
          allowUiUpdates = false;
          options.path = ./grafana/dashboards/ops;
        }
        {
          name = "fitness";
          folder = "Fitness";
          allowUiUpdates = false;
          options.path = ./grafana/dashboards/fitness;
        }
        {
          name = "music";
          folder = "Music";
          allowUiUpdates = false;
          options.path = ./grafana/dashboards/music;
        }
        {
          name = "chatting";
          folder = "Chatting";
          allowUiUpdates = false;
          options.path = ./grafana/dashboards/chatting;
        }
      ];
    };

    provision.alerting = import ./grafana/alerting { inherit lib; };
  };

}
