# CI-built NixOS deployment

The deploy workflow builds the system closure for Falcon, Kite, Magpie and
Partridge on GitHub's x86_64 runners. It pushes each complete runtime closure
to a signed, public Cachix cache before Terraform applies or any host switches.
Fourth then asks each host to switch to the exact commit and store path that CI
built. The host fetches the closure with local builds disabled, checks the
resulting path, and retains the existing rollback and service health checks.
A missing cache object or mismatched path fails before activation.

This applies to every repo-managed NixOS host. It does not change Terraform's
execution location. GitHub Actions remains the build machine; Fourth remains
the deploy orchestrator.

## Setup needed before merging

1. Create a **public** Cachix cache for Lab. Record its cache name and public
   signing key. Set GitHub repository variables `LAB_NIX_CACHE_NAME` and
   `LAB_NIX_CACHE_PUBLIC_KEY` to those values.
2. Create a cache write token scoped to that cache and set the repository
   secret `LAB_NIX_CACHE_AUTH_TOKEN`. Only CI receives it. Hosts receive the
   public signing key and URL for each switch.
3. Bootstrap the new `remote-deploy.nix` wrapper on each host with a reviewed
   manual switch. Existing installed wrappers accept only the old `lab-switch`
   command; they cannot accept the pinned command until this code is running.
   In particular, check Partridge's build plan before its bootstrap switch.
4. Verify Fourth's `/opt/deploy/run.sh` dispatches `nix-switch` with arguments
   to `deploy/nix-switch.sh`, as it already does for `plan-terraform`. Install
   the new deploy script on Fourth before running this workflow.

Until the cache variables and token are set, the deploy workflow fails before
Terraform or any host switch. Do not merge before the bootstrap is ready:
the currently installed host wrapper rejects the new command.

The cache must retain known-good closures for rollback. Existing local NixOS
generations remain available offline. Cachix's public cache also makes the
runtime closure downloadable by others, so do not put runtime secrets in Nix
store outputs.
