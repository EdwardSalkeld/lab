# Skip repeated automated updates

Bot comments such as preview build updates can start a full agent session even
when they repeat information already received. Chatting already has a small
notification checker for this. This configuration enables **enforcement**:
clear routine updates are skipped before they start agent work.

For each eligible bot comment, the checker compares the message with earlier
versions of that same comment and asks a small model whether it adds anything
useful. The instructions come from `notifications/rules.json` on the memory
repository's freshly fetched main branch. The application stays generic;
specific notification meanings remain in memory.

The observation trial forwarded four real updates. Captured versions on Rum and
Popcorn #220 showed a failure, a retry starting on a new commit, and a successful
preview. Keep the failure and success; skip the retry progress. The clarified
memory policy was replayed against these versions and a constructed repeated
success before this rollout. See memory's
`notifications/evaluation-2026-11-10.jsonl` for the labelled cases. Failures,
successful recoveries, newly usable previews and unfamiliar messages stay useful.

## Configuration

The worker receives:

- `CHATTING_NOTIFICATION_TRIAGE_MODE=enforce`
- `CHATTING_NOTIFICATION_RULES_REPO=/srv/chatting/workspace/memory`

It reuses the worker's existing SOPS-managed `TYPESAFE_API_KEY` and writable
state directory. No additional secret or application release is needed.
Deploying the changed service definition restarts the worker manager to load
the settings; running executors use the existing restart/reconnection behaviour.
Classification adds a small model call and a bounded rules fetch for each
eligible bot update. Human requests, direct mentions and registered run results
keep their normal path. Unavailable or uncertain classification forwards events.

## Check after deployment

Confirm the active worker environment has the two settings above. Then inspect:

    journalctl -u chatting-worker.service --since '30 minutes ago' --no-pager | grep notification_triage

New eligible bot updates should produce `mode=enforce` records with rule
revision, probability, compared event IDs and both decisions:

- `forward=false`: the checker skipped the update (attention probability at
  most 0.3). Confirm no executor starts for that event.
- `forward=true`: the update needs attention or used the conservative fallback.
- `would_forward` matches the decision in enforcement mode.

The comparison state lives at
`/var/lib/worker/chatting-worker.db.notifications`. Log records omit the comment
body; the private state database contains comparison bodies. A lack of log
records before any eligible update arrives is not an activation test. Investigate
`notification_triage_disabled` or `notification_triage_unavailable` before
treating an absence of decisions as successful observation.

The next audit should compare actual skips against the original comments,
especially failures and recoveries. Existing cached decisions are retained;
enforcement applies to new decisions without replaying old events. To stop
skipping while retaining observations, set `observe` and deploy normally.
Set `off` to disable the checker entirely.
