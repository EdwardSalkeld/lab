# Partridge build incident — 25 September 2026

## What happened

Merging [PR #319](https://github.com/EdwardSalkeld/lab/pull/319) started the normal deploy. It updated the NixOS and sops-nix pins, among other dependencies. The deploy asked Partridge to run `nixos-rebuild switch` **on the VM**. Nix began building a new system there at about 12:43 UTC. The switch was cancelled at 16:08 UTC, before the new system was activated.

The build included the Go applications `bitwarden-mirror`, `exercise-tracker`, and `octopus-dl`. At 14:39 UTC it also started `sops-install-secrets`, the Go helper that sops-nix uses to install secrets during activation. This was **not** a build of the `sops` command. Inspection inside the VM found its Go compiler working on `github.com/aws/aws-sdk-go-v2/service/s3`, an indirect dependency of the helper; it does not imply that Partridge uses AWS for secrets.

## Why it built

The changed pins gave Nix different build inputs and therefore different output identities, even where application source had not changed. The deploy runs on the target host; successful PR builds on GitHub runners do not put their outputs into Partridge's Nix store. Nix built the required outputs locally when it did not substitute them. The build log and process list prove that local compilation occurred. They do **not** establish why a matching substitute was unavailable or unused.

The new system needed an output for `sops-install-secrets` because sops-nix is part of Partridge's configuration. It did **not** inherently need that output to be *compiled on Partridge*; Nix can use an already built matching output. The dependency update was not needed to keep the previously running system serving traffic.

## Why the VM became unresponsive

Partridge has two virtual CPUs, 4 GiB RAM, and a 24 GiB root disk. During the build it had about 523 MiB available RAM, no swap, and 2.5 GiB free disk space. Measured I/O pressure reached roughly 100% in the VM (82% with all runnable tasks stalled) and 80% on its Proxmox host, sol (53% fully stalled). The observed Go compiler had accumulated only 49 seconds of CPU time after about 44 minutes alive; over the next 49 seconds it gained one CPU second and 188 major page faults. Nix, Forgejo, and a PostgreSQL process were observed waiting on disk I/O. This points to severe shared storage contention and memory pressure making the build and normal services wait for reads and writes, rather than a CPU-bound compilation alone. There is no evidence of an out-of-memory kill or a full disk.

SSH timed out, and PostgreSQL exporter requests took several seconds or timed out. Those exporter failures do not prove PostgreSQL itself stopped. The new NixOS generation had not activated, so service disruption happened **during the build**, before any configuration switch.

## End state

Cancelling the [deploy run](https://github.com/EdwardSalkeld/lab/actions/runs/36136146127) did not immediately stop the build inside Partridge. Its deploy/build process tree was then terminated through the Proxmox guest agent. No reboot or PostgreSQL restart was needed. Exporters returned quickly again and the VM remained on its previous NixOS generation. [PR #320](https://github.com/EdwardSalkeld/lab/pull/320) reverted #319; its subsequent [deploy run](https://github.com/EdwardSalkeld/lab/actions/runs/36162929764) completed successfully.

Sources: [#319 deploy log](https://github.com/EdwardSalkeld/lab/actions/runs/36136146127), [sops-nix helper derivation at the #319 pin](https://github.com/Mic92/sops-nix/blob/2bd00bd9bb35fe6d114888c8f1c2e946c541dd8f/pkgs/sops-install-secrets/default.nix), and live VM/Proxmox process, memory, and I/O pressure observations made during the incident.
