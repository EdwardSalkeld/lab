# Chatting on Lab

Chatting is the app; this repository owns its Lab deployment. App configuration
and protocol documentation lives in the [Chatting repository](https://github.com/EdwardSalkeld/chatting/tree/main/docs).
The installed values here describe Lab, not every Chatting installation.

## Deployment

Lab deploys Chatting on `magpie`:

- `flake.nix` builds `chatting-handler` from `go/handler`, wraps
  `python -m app.worker.main` as `chatting-worker`, and builds `bbmb-server`.
- `nixos/hosts/magpie/chatting.nix` defines the systemd units.
- `nixos/hosts/magpie/chatting-config.nix` renders `/etc/chatting/handler.json`
  and `/etc/chatting/worker.json`.
- `nixos/hosts/magpie/chatting-secrets.nix` renders the secret env files with
  sops-nix. Config refers to secrets by env-var name (the `*_env` keys).

After Chatting CI passes on `main`, Chatting's
`.github/workflows/open-lab-deploy-pr.yml` currently opens a lab PR that bumps
the `chatting` flake input. Merging and switching that PR is the deploy.

### Python runtime upgrades

Chatting requires Python 3.14 or newer. Lab selects Python 3.14 explicitly for
both the worker wrapper and the worker service's helper commands. The worker
package build compiles the app and runs the installed wrapper with `--help`,
so incompatible syntax or missing startup dependencies fail before deployment.

Lab selects its interpreter independently of Chatting's project configuration.
Bumping only the `chatting` flake input does not upgrade Python. When upgrading
the interpreter in future:

- In lab's `flake.nix`, use
  update `chattingWorkerPython`, currently
  `pkgs.python314.withPackages (ps: [ ps.croniter ]);`.
- In `nixos/hosts/magpie/chatting.nix`, select `pkgs.python314` in the worker
  service's `path` to match, keeping executor helper commands on the same minor
  version. Changing Magpie's `environment.systemPackages` entry is optional for
  interactive shells.
- Build `.#chatting-worker` and Magpie's system configuration, then deploy
  through lab's usual switch process with the updated `chatting` input.

Lab's locked nixpkgs already provides Python 3.14.7 and a working
`python314.withPackages` environment with croniter (checked 2026-10-24); no
nixpkgs update or custom Python build is needed. Nix controls the patch release
and supplies dependencies; deployment does not run `uv sync`.

The supervisor generation includes `sys.executable` and the environment. After
the worker manager restarts, idle supervisors are replaced with the new runtime;
busy supervisors finish their current task first. Allow them to drain and check
the new worker/supervisor interpreters before declaring the upgrade complete.

## Services and credentials

`nixos/hosts/magpie/chatting.nix` defines `chatting-bbmb`,
`chatting-handler` and `chatting-worker`. BBMB listens on 9876 with metrics on
9877; the handler uses 9464 for metrics/admin and loopback 9467 for egress;
the worker activity UI uses 9465. Check the Nix configuration for installed
addresses and access rules.

The handler receives integration secrets through SOPS-rendered environment
files. `gh` must be authenticated as the handler user for GitHub polling and
issue comments. Codex must be logged in as the worker user; use
`scripts/magpie-codex-reauth.sh` to restore that login.

The worker unit preserves supervisors across manager restarts. Its systemd
settings must meet the app's supervisor requirements, including `KillMode=process`,
shared temporary storage and a short persistent worker-owned `TMPDIR`.
Runtime and unit changes require busy supervisors to drain before verification.

## Retention and inspection

`nixos/hosts/magpie/chatting-prune.nix` deletes handler and worker database rows
older than 30 days each week. The personal inbox database and cache are not
pruned. The app itself has no built-in database retention.

```sh
sqlite3 /var/lib/worker/chatting-worker.db "select run_id, result_status, created_at from run_records order by created_at desc limit 20;"
journalctl -u chatting-handler -u chatting-worker
```

## Public webhook ingress

The deployment path is public TLS at `hooks.alcachofa.faith` on Falcon, verified
HTTPS over Tailscale to Magpie Nginx (SNI and Host `hooks.alcachofa.faith`), then
HTTP to `127.0.0.1:9468`. Both proxies forward only the exact probe and GitHub paths.
Requests are limited to 64 KiB and the public proxy enforces a global 10 requests
per second budget with a burst of 20. The handler has read/write/header timeouts.

The proxy and receiver can be rolled out independently; an unavailable
backend must produce a gateway error. Verify external transit from outside
the Tailnet:

```sh
curl --fail-with-body -i https://hooks.alcachofa.faith/webhooks/test \
  -H 'Content-Type: application/json' -d '{"probe":"external-transit"}'
```

Match `X-Request-ID` with `webhook_received` in the handler journal. Verify GET
returns 405, unrelated paths return 404, an oversized body returns 413, and an
unavailable backend returns a gateway error. Public probe bodies are logged;
do not send secrets.

The GitHub signing secret is supplied by a SOPS-rendered environment file.
App behavior and webhook filtering are documented upstream; installed App
registration details follow.

### Live GitHub task delivery

Lab enables `github_webhook_delivery_enabled` and empties `github_repositories`
to disable the previous assignment/review polling connector. GitHub email
notifications for Billy's account were disabled separately by Edward. GitHub
App installation coverage is managed in GitHub; it is independent of these
handler settings.

The pinned Chatting version includes assignment-to-watch support (#324).
Registered PR feedback returns to its owning work item; new assignments/tag-ins
get a dedicated GitHub item. Own actions and routine workflow progress/success
remain filtered. The separate experimental CI ownership proposal is not included
in this rollout: workflow events lacking PR context still remain held, without
automatic worker investigation. Releases remain opt-in and are not enabled here.

After deployment, correlate a new externally generated assignment/comment with
its `github_webhook_received` receipt, `mode: queued`, and the resulting webhook
task in the work-item activity view. Confirm the expected work item/workspace
and app-server session are used. No synthetic actionable events are needed.
Logging-only historical events are not replayed automatically. Set delivery back
to false to pause webhook tasks; restore the polling selectors as well if
switching back to polling. Pausing does not discard already pending tasks.

### App registration

As checked on 2026-10-26, BillyBotApp subscribes to issues, issue comments, pull
requests, reviews, review comments/threads, workflow runs and releases. Its
Contents, Issues and Pull requests permissions are read-only. GitHub may also
send ping and installation lifecycle events, which are authenticated and logged.
The original bootstrap manifest below describes the earlier release-only setup.

[github-app-manifest.json](github-app-manifest.json) contains the registration
settings. `public: true` allows the BillyAcachofa-owned app to be installed on
Edward's repository; publication to Marketplace is not needed. Choose selected
repositories when installing.

GitHub does not offer standalone App registration using a personal access token.
The [manifest flow](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest)
starts with a signed-in browser POST to `https://github.com/settings/apps/new`,
then exchanges its temporary code through
`POST /app-manifests/{code}/conversions`. That flow generates its own webhook
secret, which must replace the receiver's secret before enabling delivery.
Alternatively, register manually using these settings and set the webhook
secret to the existing receiver secret. Do not paste secrets into issues or logs.

This [prefilled registration form](https://github.com/settings/apps/new?name=Billy%20Chatting%20Webhook&url=https%3A%2F%2Fgithub.com%2FEdwardSalkeld%2Fchatting&description=Logging-only%20GitHub%20release%20webhook%20for%20Chatting&public=true&contents=read&webhook_active=true&webhook_url=https%3A%2F%2Fhooks.alcachofa.faith%2Fwebhooks%2Fgithub&events%5B%5D=release&request_oauth_on_install=false)
can be used while signed into BillyAcachofa. GitHub requires entering the secret
in the form itself; it cannot be supplied through URL parameters. The encrypted
receiver secret is also stored in Billy's versioned memory secrets as
`github/chatting-webhook` for secure retrieval during registration.

After merging and deploying Chatting and Lab, check an unsigned request returns
401. Send a signed ping, match its returned request ID in the handler journal,
then use GitHub's App delivery page to confirm a real delivery received HTTP 200.
Finally trigger a release in the selected repository and verify its delivery ID
in `github_webhook_received` logs. A synthetic signed ping alone does not prove
that an App was registered or installed successfully.
