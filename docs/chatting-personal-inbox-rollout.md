# Chatting personal inbox: deployment checklist

Everything magpie needs before the personal mailbox workflow can be switched on.
The Nix side of this is already in `nixos/hosts/magpie/`; the rest is values
only you can get. The connector itself ships disabled, so merging the Nix is
safe before any of the below is done.

Background and the staged rollout are in the chatting repo at
`docs/connectors/personal-inbox.md`.

## 1. Fastmail

**Folders.** Create the three the config names. They do not have to be these,
but the names in `chatting-config.nix` must match exactly, and an ambiguous
name fails handler startup rather than guessing:

- `Triage/News`
- `Triage/Orders`
- `Triage/Actions`

Review deliberately has no folder, so mail the workflow could not classify
stays in the inbox and the inbox becomes the queue worth looking at.

**API token.** Settings → Privacy & Security → Connected apps & API tokens →
New API token, type **JMAP**, scope **Email**. Read-only is enough to watch it
run in dry-run, but filing needs write, so issue the real one without
read-only. Copy it before closing the dialog; it is not shown again.

## 2. Telegram

Chat ids for the three destinations. They can all be the same chat to start:

- orders
- actions (also receives review alerts)
- digest

Message the existing bot, then read `chat.id` from
`https://api.telegram.org/bot<TOKEN>/getUpdates`. The bot token itself is
already deployed as `chatting/telegram_bot_token` and is reused.

## 3. Linear

A team UUID, optionally a project UUID, and a personal API key with access to
them. Action mail creates an issue there.

## 4. Secrets

Two new values in `nixos/hosts/magpie/secrets/chatting.json`:

- `personal_jmap_token`
- `personal_linear_key`

**These must exist before the host evaluates.** sops-nix fails activation on a
declared key it cannot find, so adding the Nix without the values breaks the
deploy for everything on magpie, not just chatting.

## 5. Fill in the config

In `nixos/hosts/magpie/chatting-config.nix`, under `personal_inbox`, replace:

- `orders_telegram_target`, `action_telegram_target`, `digest_telegram_target`
- `linear_team_id`

Check `digest_at` and `timezone` suit you — the digest is a daily round-up at a
wall-clock time, not a per-message delay.

## 6. Turn it on, in stages

1. `enabled = true` with `dry_run = true`. Mail is read and classified, nothing
   is sent, moved or ticketed. Note that dry-run suppresses effects, not model
   calls: your mail reaches TypeSafe and Codex from the first poll.
2. Inspect what it would have done, on the handler's loopback admin server:
   `curl -s http://127.0.0.1:9467/api/personal-inbox | jq`. Read `steps` for
   per-stage health, and `effect_counts` for anything needing reconciliation.
3. `dry_run = false`. Notifications and tickets go out for newly classified
   mail. Previews from stage 1 stay previews and are never replayed.
4. Leave the `folders` map in place throughout — filing only starts once dry
   run is off.

## Already handled

- `TYPESAFE_API_KEY` is in the worker env and is reused; classification needs
  no new worker secret.
- Summaries use the worker's existing Codex login, so there is no second model
  credential. `CHATTING_PERSONAL_SUMMARY_MODEL` is set in the unit because
  Codex is invoked with `--ignore-user-config` and so does not read the model
  from `codex-config.toml`.
- `CHATTING_PERSONAL_CACHE_PATH` lives under `/var/lib/worker`, and the
  handler database under `/var/lib/handler`. Both are already in their units'
  `ReadWritePaths`.
