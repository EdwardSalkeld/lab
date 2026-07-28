{ ... }:

# Declarative render of the chatting handler/worker runtime configs into
# /etc/chatting. These files were previously produced by the chatting repo's
# manual `deploy/host_runtime/render_runtime_config.py` step and hand-installed,
# which left them as host state outside Nix. Generating them here makes
# `nixos-rebuild switch` the single source of truth, matching every other lab
# service.
#
# Secrets are intentionally absent: the handler references them by env-var name
# (the *_env fields) and reads the actual values from /etc/chatting/handler.env
# and worker.env, which remain host state for now. Moving those onto sops-nix is
# a planned follow-up.
#
# live-schedule.local.json (referenced by schedule_file) is also left as host
# state on purpose so the prompt schedule can be edited without a rebuild.

let
  workspaceDir = "/srv/chatting/workspace";
  contextRefs = [ "repo:${workspaceDir}" ];

  handlerConfig = {
    db_path = "/var/lib/handler/chatting-message-handler.db";
    bbmb_address = "127.0.0.1:9876";
    # Bind metrics on all interfaces so Partridge's Prometheus can scrape the
    # handler; the magpie firewall only opens 9464 to the LAN.
    metrics_host = "0.0.0.0";
    poll_interval_seconds = 30;
    poll_timeout_seconds = 2;
    allowed_egress_channels = [
      "email"
      "telegram"
      "log"
      "telegram_reaction"
    ];

    imap_host = "imap.fastmail.com";
    imap_port = 993;
    imap_username = "edsalkeld@fastmail.com";
    imap_password_env = "CHATTING_IMAP_PASSWORD";
    imap_mailbox = "Chatting";
    imap_search = "UNSEEN";

    smtp_host = "smtp.fastmail.com";
    smtp_port = 465;
    smtp_username = "edsalkeld@fastmail.com";
    smtp_password_env = "CHATTING_SMTP_PASSWORD";
    smtp_from = "billy@alcachofa.faith";
    smtp_starttls = false;

    telegram_enabled = true;
    telegram_bot_token_env = "CHATTING_TELEGRAM_BOT_TOKEN";
    telegram_api_base_url = "https://api.telegram.org";
    telegram_poll_timeout_seconds = 20;
    telegram_allowed_chat_ids = [
      "8605042448"
      "-4974044081"
      "-1004974044081"
      "-5060255147"
      "-5273941835"
      "-541767767"
      "-5594899826"
    ];
    telegram_allowed_channel_ids = [
      "-1003738951842"
    ];
    telegram_context_refs = contextRefs;
    telegram_attachment_dir = "/var/lib/handler/telegram-attachments";

    context_refs = contextRefs;
    auxiliary_ingress_context_refs = null;

    schedule_file = "/etc/chatting/live-schedule.local.json";

    github_assignee_login = "billyacachofa";
    github_repositories = [
      "brokensbone/*"
      "EdwardSalkeld/*"
    ];
    github_context_refs = null;
  };

  workerConfig = {
    db_path = "/var/lib/worker/chatting-worker.db";
    bbmb_address = "127.0.0.1:9876";
    max_attempts = 2;
    poll_timeout_seconds = 20;
    sleep_seconds = 1.0;
    codex_command = "codex exec --dangerously-bypass-approvals-and-sandbox";
    codex_working_dir = workspaceDir;
  };
in
{
  environment.etc."chatting/handler.json".text = builtins.toJSON handlerConfig;
  environment.etc."chatting/worker.json".text = builtins.toJSON workerConfig;
}
