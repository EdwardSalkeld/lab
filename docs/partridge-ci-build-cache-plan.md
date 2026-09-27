# Reuse CI builds on Partridge

Status: proposal for review. This document changes no deployment behaviour.

## Goal

Keep Partridge as a deploy target while avoiding source compilation on its 2-CPU,
4-GiB VM. CI already builds its NixOS system for PRs, but those store paths stay
on the GitHub runner. Partridge cannot use the existing Kite GitHub Actions
cache: that cache is only restored to other Actions runners.

## Proposed handoff

1. Use a dedicated signed Nix binary cache for Lab, such as Cachix. Keep its
   **write token** in GitHub Actions secrets. Configure Partridge with the cache
   URL and **public signing key**; it does not receive the write token.
2. On each push to `main`, build the exact Partridge system closure on an
   x86_64 GitHub runner and push that closure to the cache. Keep the current PR
   build as a check, but publish only from trusted `main`.
3. Make the existing deploy job wait for that publish job before asking fourth
   to switch Partridge. The host's switch should use the same `main` revision
   that was built, fetch signed substitutes, and refuse local builds. A missing
   cache path fails the deploy before switching services.
4. Keep the other hosts' deployment behaviour unchanged. The first rollout of
   the cache configuration needs a separately checked bootstrap, because the
   current Partridge generation does not yet trust the new cache.

## Why publish the whole closure

Publishing only the Go programs would leave Partridge to build any other
uncached output. The whole closure is precise: Nix transfers the paths the
system actually references, while already cached paths are reused. It also
lets the no-local-build rule be absolute instead of guessing which derivations
are cheap enough for the VM.

## Safety checks before enabling the switch

- Create the cache and record its public signing key; add its write token to
  repository secrets. Neither exists in this repo today.
- In CI, compare the built system store path to the path Partridge will select
  for the same commit. Pin the switch to that commit rather than refreshing
  moving `main` independently.
- Test a cache miss: the deploy must fail with the old generation still active.
- Test a successful fetch and switch, then verify Grafana and PostgreSQL health.
- Check cache retention and size so old, known-good closures remain available
  for rollback. Existing local NixOS generations should still work offline.

The cache adds a service and credentials to maintain. It avoids compiling on
Partridge; it does not reduce the amount of compilation needed in CI. The
unstable-pin and exporter PRs are independent of this proposal and still use
the current on-host deployment path if merged first.
