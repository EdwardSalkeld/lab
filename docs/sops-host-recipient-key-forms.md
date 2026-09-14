# SOPS host recipient key forms

## Summary

A host's SSH host key can be written as a SOPS recipient in two different ways,
and they are not interchangeable. `sops-nix` loads only one of them. Declaring a
host in the wrong form leaves that host unable to decrypt its own secrets, which
surfaces as missing files under `/run/secrets` and services failing to start
after a deploy.

This document records the two forms, how to tell which one a host actually uses,
and the evidence behind keeping the repo on the converted form.

## The two forms

Both derive from the same `/etc/ssh/ssh_host_ed25519_key`, but they produce
different, mutually unreadable recipient stanzas in an encrypted file.

| form | looks like | produced by |
| --- | --- | --- |
| converted | `age162pm4ssrw8ngrk…` | `ssh-to-age` (X25519 conversion) |
| native | `ssh-ed25519 AAAAC3Nza…` | age's own SSH recipient support |

An identity in one form will not open a stanza written in the other. They look
like different keys and are in fact the same key, which is the main source of
confusion when reading `.sops.yaml` next to an encrypted file.

The same applies to operator keys. `edward_mac` appears as
`ssh-ed25519 AAAA…Dzhd…` in `.sops.yaml` but as
`age1rz69760drrjyrcwv…` inside Magpie's secret files — again, one key, two
notations.

## Which form sops-nix uses

`sops-install-secrets` converts the host key and loads the result as an age
identity. It logs exactly what it imported during activation:

```
sops-install-secrets: Imported /etc/ssh/ssh_host_rsa_key as GPG key with
  fingerprint df4ed9144d6613c2f57abbb04ee1ae4ed3d5e949
sops-install-secrets: Imported /etc/ssh/ssh_host_ed25519_key as age key with
  fingerprint age162pm4ssrw8ngrk6zdkztuvc4ez4mzt8jwnvk2wn7jnkye9393ujs8rkgsg
```

Two imports, and the ed25519 key is registered in converted form. Nothing
registers the raw SSH public key as a native age-SSH identity.

That fingerprint is reproducible from the public key alone:

```sh
ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub
# age162pm4ssrw8ngrk6zdkztuvc4ez4mzt8jwnvk2wn7jnkye9393ujs8rkgsg
```

Confirmed by decrypting a Magpie secret on Magpie with that converted identity:

```sh
SOPS_AGE_KEY="$(ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key)" \
  sops --decrypt nixos/hosts/magpie/secrets/chatting.json
# DECRYPT OK
```

## Why PR #254's Magpie change was wrong

PR #254 adds M1 as a recovery recipient, which is correct. Alongside that it
changed the `&magpie` anchor from the converted form to Magpie's raw
`ssh-ed25519` public key, and re-encrypted Magpie's secrets accordingly.

That removes `age162pm4ssrw8ngrk…` — the only identity the activation log shows
Magpie loading — from the recipient list of `chatting.json` and
`forgejo-runner.json`. On the next deploy `sops-install-secrets` would have no
usable identity for those files, so `/run/secrets/chatting/*` and
`/run/secrets/forgejo-runner/token` would not be rendered and the `chatting`
services would fail to start.

The key in the PR is genuinely Magpie's host key. The problem is the notation,
not the machine.

### Magpie's key handling was not broken beforehand

The change was made on the premise that Magpie's key reading was already
broken. It was not. On the running host:

```
/run/secrets/chatting          4 files: imap_password memory_secret_passphrase
                                        smtp_password telegram_bot_token
/run/secrets/forgejo-runner    1 file:  token          (40 bytes)
/run/secrets/rendered          3 files: chatting-handler.env
                                        chatting-worker.env
                                        forgejo-runner.env
```

All present and non-empty, and the identity Magpie derives matches what
`.sops.yaml` declared on `main`. Secrets were rendering correctly.

### What is actually inconsistent

Magpie's own key was already consistent with the other hosts. The real
divergence is how the operator key is stored inside each host's secret files:

| host | operator key (`edward_mac`) | host's own key |
| --- | --- | --- |
| partridge | `ssh-ed25519 …Dzhd…` (native) | `age1p46dg…` (converted) |
| kite | `ssh-ed25519 …Dzhd…` (native) | `age13h355…` (converted) |
| magpie | `age1rz6976…` (**converted**) | `age162pm4…` (converted) |

Every host stores its own key in converted form. Only Magpie stores the
operator key in converted form rather than native. That is the cell that is out
of line, and it lives in the encrypted files rather than in `.sops.yaml`.

Because `.sops.yaml` declares `edward_mac` in native form, `sops updatekeys`
reports a diff on Magpie's files. That diff is a notation mismatch, not a
failure, and is the most likely reason the original change was thought to be a
fix.

## The rule

- **Host entries in `.sops.yaml` stay in converted (`age1…`) form.** That is
  what `sops-nix` loads at activation.
- **Operator entries stay in native (`ssh-ed25519 …`) form.** Operators decrypt
  with the `sops` CLI, which reads `~/.ssh/id_ed25519` directly and prompts for
  the passphrase.

Bringing Magpie in line therefore means re-keying its files so the operator key
is stored natively, while leaving the `&magpie` anchor alone:

```sh
sops updatekeys nixos/hosts/magpie/secrets/chatting.json \
                nixos/hosts/magpie/secrets/forgejo-runner.json
```

This has to be run by a human: `updatekeys` decrypts before re-wrapping, so it
needs an SSH key passphrase on a terminal.

## Verifying a host after a recipient change

Confirm the identity the host loads still appears as a recipient on its files
before deploying:

```sh
# what the host loads
ssh <host> 'sudo journalctl -b | grep "sops-install-secrets: Imported"'

# what the files are encrypted to
grep -oE '"?recipient"?: ?"?[^"]*' nixos/hosts/<host>/secrets/*
```

After deploying, check the secrets actually rendered rather than trusting that
activation succeeded:

```sh
ssh <host> 'sudo find /run/secrets/ -type f -exec stat -c "%s %n" {} \;'
```

An empty or missing file here means decryption failed even if the unit is
active, because consumers read these paths lazily.
