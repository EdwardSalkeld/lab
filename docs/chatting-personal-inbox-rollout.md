# Chatting personal inbox: deployment checklist

> **Merge order matters.** The handler refuses to start on a config key it does
> not recognise, so `personal_inbox` must not reach magpie before a chatting
> release that understands it. Deploying early takes the existing bot mailbox
> down with it. Land the chatting side on its main and let a release build
> before merging this.

Everything magpie needs before the personal mailbox workflow can be switched on.
The Nix side of this is already in `nixos/hosts/magpie/`; the rest is values
only you can get. The connector itself ships disabled, so merging the Nix is
safe before any of the below is done.

Background and the staged rollout are in the chatting repo at
`docs/connectors/personal-inbox.md`.

## 1. Fastmail

**Folders.** Done. Create the three the config names. They do not have to be these,
but the names in `chatting-config.nix` must match exactly, and an ambiguous
name fails handler startup rather than guessing:

- `Triage/News`
- `Triage/Orders`
- `Triage/Actions`

Review deliberately has no folder, so mail the workflow could not classify
stays in the inbox and the inbox becomes the queue worth looking at.

**API token.** Done. Settings → Privacy & Security → Connected apps & API
tokens → New API token, type **JMAP**, scope **Email**, not read-only, since
filing needs write. Verified against the live account: all three folders above
resolve unambiguously and a no-op `Email/set` is accepted, so the token can
file mail.

## 2. Telegram — done

Chat ids for the three destinations. They can all be the same chat to start:

- orders
- actions (also receives review alerts)
- digest

Message the existing bot, then read `chat.id` from
`https://api.telegram.org/bot<TOKEN>/getUpdates`. The bot token itself is
already deployed as `chatting/telegram_bot_token` and is reused.

## 3. Secrets — done

`personal_jmap_token` is encrypted in
`nixos/hosts/magpie/secrets/chatting-personal.json`, readable by Ed's two keys,
the vault backup key and magpie's host key.

It is a file of its own rather than another entry in `chatting.json` because
adding a value to an existing sops file needs that file's data key, and so the
private key of one of its recipients. Creating a new file needs only their
public keys, which is why this could be done without unlocking anything. The
Jev key lives in its own file for the same reason.

## 4. Fill in the config — done

All three Telegram targets point at one chat to begin with; split them later by
giving each its own id. Check `digest_at` and `timezone` suit you — the digest
is a daily round-up at a wall-clock time, not a per-message delay.

## 5. Turn it on, in stages

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

## Later, optional: Linear ticketing

Action mail raises a Linear issue as well as alerting, but only once a team is
configured. Until then it is alerted and filed like everything else, which is
deliberately the smallest thing that works.

To add it: a team UUID (and optionally a project), a Linear personal key with
access to them added to the secrets as `personal_linear_key`, that placeholder
restored in the handler env template, and `linear_team_id` filled in. A
configured team whose key is missing logs that ticketing is disabled and
carries on rather than failing startup.

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
