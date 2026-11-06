# Trying the automated notification checker

Bot comments such as preview build updates can start a full agent session even
when they repeat information already received. Chatting already has a small
notification checker for this. This configuration turns on its **observation
mode**: it records what it would skip while continuing to deliver every message
to the agent.

For each eligible bot comment, the checker compares the message with earlier
versions of that same comment and asks a small model whether it adds anything
useful. The instructions come from `notifications/rules.json` on the memory
repository's freshly fetched main branch. The application stays generic;
specific notification meanings remain in memory.

During this trial, repeated progress and unchanged successful previews still
reach the agent. We gain real examples of proposed skips to review. Failure,
recovery, new-commit and unfamiliar notifications should remain useful; review
those cases before deciding to let the checker suppress anything. The existing
replay examples alone do not establish how it behaves on real traffic.

## Configuration

The worker receives:

- `CHATTING_NOTIFICATION_TRIAGE_MODE=observe`
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

New eligible bot updates should produce `mode=observe` records with rule
revision, probability, compared event IDs and both decisions:

- `forward=true`: the message was allowed through during the trial.
- `would_forward=false`: the checker thinks it could have skipped that message.
- `would_forward=true`: it thinks the message needs attention, or used the
  conservative fallback.

The comparison state lives at
`/var/lib/worker/chatting-worker.db.notifications`. Log records omit the comment
body; the private state database contains comparison bodies. A lack of log
records before any eligible update arrives is not an activation test. Investigate
`notification_triage_disabled` or `notification_triage_unavailable` before
treating an absence of decisions as successful observation.

The next audit should compare proposed skips against the original comments and
resulting agent work, including failures and recoveries. Enabling suppression
(`enforce`) is a separate rollout decision after that review. To stop the
trial, set the mode to `off` and deploy through the usual process.
