# CI-built NixOS deployment

The deploy workflow builds the system closure for Falcon, Kite, Magpie and
Partridge on GitHub's x86_64 runners. It pushes each complete runtime closure
to a signed, public Cachix cache before Terraform applies or any host switches.
Fourth then asks each host to switch to the exact commit and store path that CI
built. The host fetches the closure with local builds disabled, checks the
resulting path, and retains the existing rollback and service health checks.
A missing cache object or mismatched path fails before activation. The host's
forced command accepts only this pinned request; it never builds a flake
reference on the host.
Magpie and Partridge also check HTTP endpoints after switching. A
`Type=simple` service can briefly report active before startup fails, so
systemd status alone is insufficient. The wrapper polls the unit and HTTP
checks every 5 seconds for up to 90 seconds, so a service that is still
starting (Loki's `/ready` answers 503 for its first 15 seconds) does not cause
a rollback. Failed HTTP checks trigger the same rollback as failed unit checks;
final recovery is checked again and reports unit status if the service still
cannot answer.
Hosts use `nix-store --realise` on the exact output path to fetch its signed runtime closure:
some NixOS scaffolding disables normal derivation substitution, so a cache-only
`nix build` is not sufficient even when the published output exists. This also
uses the normal NixOS cache for upstream paths which Cachix deliberately omits
([Cachix FAQ](https://docs.cachix.org/faq)). No derivation path is realised.

This applies to every repo-managed NixOS host. It does not change Terraform's
execution location. GitHub Actions remains the build machine; Fourth remains
the deploy orchestrator.

## Pull request cache access

The PR host-build matrix reads the same public cache using
`LAB_NIX_CACHE_NAME`, with `cachix/cachix-action` in read-only mode
(`skipPush: true`) and no authentication token. Every selected host can reuse
cached outputs for both the PR build and its comparison build of `main`.
Deploy remains the cache publisher; there is no separate cache-warming
workflow or Kite-only GitHub Actions Nix store cache.

Deploy publishes runtime closures, so build-only dependencies may still need
to be built when a PR changes an output. PR builds retain normal source-build
fallback for cache misses.

## Cache and trust configuration

1. Lab uses a **public** Cachix cache. The GitHub repository variables
   `LAB_NIX_CACHE_NAME` and `LAB_NIX_CACHE_PUBLIC_KEY` hold its name and public
   signing key. Until they are set, the deploy workflow fails before Terraform
   or any host switch.
2. The repository secret `LAB_NIX_CACHE_AUTH_TOKEN` is a write token scoped to
   that cache. Only CI receives it. Hosts receive the public signing key and
   URL for each switch.
3. The installed wrapper pins `alcachofa.remoteDeploy.cacheName` and
   `cachePublicKey` and rejects a request that supplies a different cache or
   key. Cache or key rotation therefore also requires an explicit host
   trust-configuration update, rolled out with the bootstrap below.

Fourth's dispatcher preserves command arguments and checks out the latest
`main` before running `deploy/nix-switch.sh`. The workflow sends one
`<host>=<system-path>` argument per flake host, and the script refuses the
request unless those are exactly the hosts on its fixed list. It then sends
each host the pinned
`lab-switch <commit> <cache-name> <cache-key> <system-path>` request.

The cache must retain known-good closures for rollback. Existing local NixOS
generations remain available offline. Cachix's public cache also makes the
runtime closure downloadable by others, so do not put runtime secrets in Nix
store outputs.

## Bootstrapping a host

A host whose installed wrapper cannot accept the current deploy request (a new
host, or a cache trust change) is switched by hand once from a CI-built
closure. Run the deploy workflow with **build_only=true** on the branch that
carries the change. This publishes signed closures and a `bootstrap-manifest`
artifact, without Terraform or host switches. An omitted/false input runs the
normal deploy.

```sh
gh workflow run deploy.yml --repo EdwardSalkeld/lab \
  --ref <branch> -f build_only=true
gh run download <successful-run-id> --repo EdwardSalkeld/lab \
  --name bootstrap-manifest --dir bootstrap-manifest
```

The artifact contains `commit` and one output path per host. Use the script
from that exact commit, copied to the host. Run as root:

```sh
./bootstrap-ci-deploy.sh plan partridge <commit> <cache-name> <cache-key> <partridge-path>
# After reviewing that output, pass its printed Current path as the last arg:
./bootstrap-ci-deploy.sh switch partridge <commit> <cache-name> <cache-key> <partridge-path> <reviewed-current-system>
```

`plan` fetches the complete signed closure, checks that the evaluated commit
produces the exact CI output, and prints the diff from the running system. It
never changes the system profile or services. If any closure object is
missing, it fails rather than compiling. `switch` requires that the running
system still matches the reviewed plan, checks the existing health units, sets
the profile to the already fetched output and activates it directly. It
restores the previous profile and activation on failure and starts the
critical units. Keep the running task out of Magpie's switch window, since its
worker may restart.

After switching, inspect `/etc/ssh/authorized_keys.d/root`: the Fourth key's
forced wrapper must accept the pinned `lab-switch` request. The next normal
deployment's logs should show cache fetching with `max-jobs 0` and no
compilation.
