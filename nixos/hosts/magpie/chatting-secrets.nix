{ config, ... }:

# Secrets for the chatting handler/worker, managed with sops-nix. The encrypted
# values live in ./secrets/chatting.json (decryptable by Ed's key and magpie's
# SSH host key). sops renders them into env files at activation, which the
# services load via EnvironmentFile — replacing the previously hand-placed
# plaintext /etc/chatting/{handler,worker}.env host state.
#
# The config JSON (chatting-config.nix) references these by env-var name, so this
# is the last piece of chatting config that lived outside Nix.

{
  sops.defaultSopsFile = ./secrets/chatting.json;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  sops.secrets = {
    "chatting/imap_password".key = "imap_password";
    "chatting/smtp_password".key = "smtp_password";
    "chatting/telegram_bot_token".key = "telegram_bot_token";
    "chatting/memory_secret_passphrase".key = "memory_secret_passphrase";
  };

  sops.templates."chatting-handler.env" = {
    owner = "handler";
    group = "handler";
    mode = "0400";
    content = ''
      CHATTING_IMAP_PASSWORD=${config.sops.placeholder."chatting/imap_password"}
      CHATTING_SMTP_PASSWORD=${config.sops.placeholder."chatting/smtp_password"}
      CHATTING_TELEGRAM_BOT_TOKEN=${config.sops.placeholder."chatting/telegram_bot_token"}
    '';
  };

  sops.templates."chatting-worker.env" = {
    owner = "worker";
    group = "worker";
    mode = "0400";
    content = ''
      BILLY_MEMORY_SECRET_PASSPHRASE=${config.sops.placeholder."chatting/memory_secret_passphrase"}
    '';
  };
}
