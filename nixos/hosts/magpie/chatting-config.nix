{ ... }:

# Declarative render of the chatting handler/worker runtime configs into
# /etc/chatting. These files were previously produced by the chatting repo's
# manual `deploy/host_runtime/render_runtime_config.py` step and hand-installed,
# which left them as host state outside Nix. Generating them here makes
# `nixos-rebuild switch` the single source of truth, matching every other lab
# service.
#
# Secrets are intentionally absent: the handler references them by env-var name
# (the *_env fields); sops-nix renders the actual values into the env files the
# services load (see chatting-secrets.nix).
#
# Schedules are no longer here either — they live in the handler DB, managed
# through the /api/schedules API and /schedules UI, so schedule_file is retired.

let
  workspaceDir = "/srv/chatting/workspace";
  workspacesDir = "/srv/chatting/workspaces";
  contextRefs = [ "repo:${workspaceDir}" ];
  codexConfig = ''
    personality = "pragmatic"
    model = "gpt-6-sol"
    model_reasoning_effort = "medium"

    [projects."${workspaceDir}"]
    trust_level = "trusted"
  '';

  handlerConfig = {
    db_path = "/var/lib/handler/chatting-message-handler.db";
    bbmb_address = "127.0.0.1:9876";
    # Prometheus now scrapes through nginx, so this need not leave the host.
    metrics_host = "127.0.0.1";
    poll_interval_seconds = 30;
    allowed_egress_channels = [
      "email"
      "telegram"
      "log"
      "telegram_reaction"
      # Lets the handler post replies back to GitHub issues/PRs via `gh issue
      # comment` (the handler runs as the BillyAcachofa gh account). Without
      # this the egress engine drops github-channel replies as disallowed.
      "github"
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

    telegram_enabled = true;
    telegram_bot_token_env = "CHATTING_TELEGRAM_BOT_TOKEN";
    telegram_api_base_url = "https://api.telegram.org";
    telegram_poll_timeout_seconds = 20;
    telegram_allowed_chat_ids = [
      "8605042448"
      "-4974044081"
      "-1004974044081"
      "-5060255147"
      "-5201675435"
      "-5273941835"
      "-5367346228"
      "-541767767"
      "-5417677674"
      "-5594899826"
    ];
    telegram_allowed_channel_ids = [
      "-1003738951842"
    ];
    telegram_context_refs = contextRefs;
    # Shared with the worker (a different OS user), not handler-private: the
    # worker/executor has to read the downloaded photo. See the tmpfiles rule
    # and the handler's ReadWritePaths in chatting.nix.
    telegram_attachment_dir = "/srv/chatting/attachments";
    # The handler refuses to send an outbound attachment whose local path falls
    # outside this allowlist (a fail-closed guard against a caller naming an
    # arbitrary file to exfiltrate). Permit the three places a legitimate
    # attachment lives: the shared attachment dir (inbound photos echoed back),
    # the shared workspace, and the per-item workspaces (files the agent
    # produced). Empty would block every outbound file attachment.
    egress_attachment_allowed_dirs = [
      "/srv/chatting/attachments"
      workspaceDir
      workspacesDir
    ];

    context_refs = contextRefs;

    github_assignee_login = "billyacachofa";
    github_repositories = [
      "brokensbone/*"
      "EdwardSalkeld/*"
    ];

    # Opt-in personal mailbox triage, separate from the bot mailbox above and
    # from the executor.
    #
    # This is live: classified mail is filed into the folders below and
    # notified. What protects the mail already classified is not this setting
    # but the effect ledger, which never replays an effect recorded as a
    # preview. Acting changes what happens to mail from here, not what
    # happened to mail already seen.
    personal_inbox = {
      enabled = true;
      # Must differ from the handler's own db_path. /var/lib/handler is already
      # in the unit's ReadWritePaths.
      db_path = "/var/lib/handler/personal-inbox.db";
      account = "personal";
      jmap_token_env = "CHATTING_PERSONAL_JMAP_TOKEN";
      # Classify what is already in the inbox, to judge the categories against
      # real mail rather than one test message. This only applies while the
      # workflow is establishing its first baseline, and one is already
      # recorded, so it does nothing until that stored state is deleted. Mail
      # it classified while the workflow was in preview stays a preview and is
      # not acted on now.
      backfill = true;
      dry_run = false;
      # Create these in Fastmail before enabling: an unknown or ambiguous name
      # fails startup rather than silently leaving mail unfiled. Action and
      # Review have no destination folder: both stay in the inbox until handled.
      folders = {
        news = "Triage/News";
        order = "Triage/Orders";
        review = "";
      };
      # Action and Review mail stay unread in the inbox.
      mark_read = [
        "news"
        "order"
      ];
      mail_link_template = "https://app.fastmail.com/mail/{folder}/{thread}.{email}?u={account}";
      orders_telegram_target = "-5495815712";
      action_telegram_target = "-5495815712";
      digest_telegram_target = "-5495815712";
      # Real mail has a long uncertain tail, so this is the dial for how much
      # of it to accept rather than hold. Everything held stays in the inbox.
      confidence_threshold = 0.8;
      digest_at = "08:00";
      timezone = "Europe/London";
      # Ticketing is off while the team is empty: action mail is still alerted,
      # it just raises no issue. Wire it up once the rest is known
      # to work, by adding the team here and personal_linear_key to the secrets.
      linear_key_env = "CHATTING_PERSONAL_LINEAR_KEY";
      linear_team_id = "";
      linear_project_id = "";
    };
  };

  workerConfig = {
    db_path = "/var/lib/worker/chatting-worker.db";
    bbmb_address = "127.0.0.1:9876";
    max_attempts = 2;
    executor_pool_size = 2;
    poll_timeout_seconds = 20;
    sleep_seconds = 1.0;
    # The work item session view renders Codex's JSON event stream live.
    codex_command = "codex exec --json --dangerously-bypass-approvals-and-sandbox";
    codex_working_dir = workspaceDir;
    workspace_root = workspacesDir;
    handler_egress_url = "http://127.0.0.1:9467/egress";
  };
in
{
  environment.etc."chatting/handler.json".text = builtins.toJSON handlerConfig;
  environment.etc."chatting/worker.json".text = builtins.toJSON workerConfig;
  environment.etc."chatting/codex-config.toml".text = codexConfig;
}
