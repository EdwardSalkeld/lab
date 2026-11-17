# Skip repeated automated updates

Bot comments such as preview build updates can start a full agent session even
when they repeat information already received. Chatting already has a small
notification checker for this. Clear routine updates are skipped before they start agent work.

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

- `CHATTING_NOTIFICATION_RULES_REPO=/srv/chatting/workspace/memory`

It reuses the worker's existing SOPS-managed `TYPESAFE_API_KEY` and writable
state directory. The installed Chatting version must include removal of the
notification modes before this setting is removed from Lab.
Deploying the changed service definition restarts the worker manager to load
the settings; running executors use the existing restart/reconnection behaviour.
Classification adds a small model call and a bounded rules fetch for each
eligible bot update. Human requests, direct mentions and registered run results
keep their normal path. Unavailable or uncertain classification forwards events.

## Check after deployment

Confirm the active worker environment has the rules repository setting above. Then inspect:

    journalctl -u chatting-worker.service --since '30 minutes ago' --no-pager | grep notification_triage

New eligible bot updates should produce `notification_triage` records with rule
revision, probability, compared event IDs and the forwarding decision:

- `forward=false`: the checker skipped the update (attention probability at
  most 0.3). Confirm no executor starts for that event.
- `forward=true`: the update needs attention or used the conservative fallback.

The comparison state lives at
`/var/lib/worker/chatting-worker.db.notifications`. Log records omit the comment
body; the private state database contains comparison bodies. A lack of log
records before any eligible update arrives is not an activation test. Investigate
`notification_triage_disabled` or `notification_triage_unavailable` before
treating an absence of decisions as successful operation.

The next audit should compare actual skips against the original comments,
especially failures and recoveries. Existing cached decisions are retained;
enforcement applies to new decisions without replaying old events. If suppression must be stopped, remove the rules repository setting and deploy normally; missing configuration forwards events.
