# CI-built NixOS deployment

The deploy workflow builds the system closure for Falcon, Kite, Magpie and
Partridge on GitHub's x86_64 runners. It pushes each complete runtime closure
to a signed, public Cachix cache before Terraform applies or any host switches.
Fourth then asks each host to switch to the exact commit and store path that CI
built. The host fetches the closure with local builds disabled, checks the
resulting path, and retains the existing rollback and service health checks.
A missing cache object or mismatched path fails before activation.
Hosts use `nix copy --from` to import the signed runtime closure explicitly:
some NixOS scaffolding disables normal derivation substitution, so a cache-only
`nix build` is not sufficient even when the published output exists.

This applies to every repo-managed NixOS host. It does not change Terraform's
execution location. GitHub Actions remains the build machine; Fourth remains
the deploy orchestrator.

## Setup needed before merging

1. Create a **public** Cachix cache for Lab. Record its cache name and public
   signing key. Set GitHub repository variables `LAB_NIX_CACHE_NAME` and
   `LAB_NIX_CACHE_PUBLIC_KEY` to those values.
2. Create a cache write token scoped to that cache and set the repository
   secret `LAB_NIX_CACHE_AUTH_TOKEN`. Only CI receives it. Hosts receive the
   public signing key and URL for each switch. The installed wrapper pins
   `alcachofa.remoteDeploy.cacheName` and `cachePublicKey` and rejects a request
   that supplies a different cache or key. Cache/key rotation therefore also
   requires an explicit host trust-configuration update.
3. Run the deploy workflow on this PR branch with **build_only=true**. This
   publishes signed closures and a `bootstrap-manifest` artifact, without
   Terraform or host switches. An omitted/false input runs the normal deploy;
   use the exact command below for bootstrap preparation.
4. Fetch and review each host's closure with `scripts/bootstrap-ci-deploy.sh
   plan`, then run its separate `switch` operation after approval. Both
   operations disable local and remote builds. In particular, inspect
   Partridge's closure diff before its bootstrap switch.
5. Verify all four hosts have the new wrapper before merging. During this
   transition it accepts the existing bare `lab-switch` command as well as the
   new pinned command, so the current main workflow remains usable. The bare
   command retains the existing on-host rebuild behavior; the new workflow
   always uses pinned, cache-only requests. Do not roll out #347 during this
   transition.

Fourth's existing dispatcher preserves command arguments and checks out the
latest `main` before running `deploy/nix-switch.sh`; it needs no update.

Until the cache variables and token are set, the deploy workflow fails before
Terraform or any host switch. Do not merge before the bootstrap is ready:
the currently installed host wrapper rejects the new command.

The cache must retain known-good closures for rollback. Existing local NixOS
generations remain available offline. Cachix's public cache also makes the
runtime closure downloadable by others, so do not put runtime secrets in Nix
store outputs.

## Build and review the bootstrap

```sh
gh workflow run deploy.yml --repo EdwardSalkeld/lab \
  --ref billy/partridge-ci-store-transfer -f build_only=true
gh run download <successful-run-id> --repo EdwardSalkeld/lab \
  --name bootstrap-manifest --dir bootstrap-manifest
```

The artifact contains `commit` and one output path per host. Use the script
from that exact commit, copied to each host; Falcon requires Edward's/root
access because Billy's account there has no sudo permission. Run as root:

```sh
./bootstrap-ci-deploy.sh plan partridge <commit> <cache-name> <cache-key> <partridge-path>
# After reviewing that output, pass its printed Current path as the last arg:
./bootstrap-ci-deploy.sh switch partridge <commit> <cache-name> <cache-key> <partridge-path> <reviewed-current-system>
```

Repeat for Falcon, Kite and Magpie. `plan` fetches the complete signed closure,
checks that the evaluated commit produces the exact CI output, and prints the
diff from the running system. It never changes the system profile or services.
If any closure object is missing, it fails rather than compiling. `switch`
requires that the running system still matches the reviewed plan, checks the
existing health units, sets the profile to the already fetched output and
activates it directly. It restores the previous profile and activation on
failure and starts the critical units. Keep the running task out of Magpie's
switch window, since its worker may restart.

After switching, inspect `/etc/ssh/authorized_keys.d/root`: the Fourth key's
forced wrapper must accept both bare and pinned `lab-switch` requests. Run a
normal deployment after merging and verify the logs show cache fetching with
`max-jobs 0` and no compilation before considering #347.
