# Proxmox Reboot Event Log - 2026-02-17

## Context

- Host: `sol`
- Purpose: Planned Proxmox host reboot
- Runbook: `runbook/proxmox-reboot.md`
- Operator: User
- Assistant: Codex

## Outcome

- Proxmox reboot completed successfully.
- Talos nodes returned healthy (`Ready`, Talos health checks `OK`).
- Traefik service returned healthy.
- Argo CD initially degraded post-reboot (controller/repo/server instability), then recovered after targeted restart + controller pod recreation.

## Timeline

- 2026-02-17: Event log created. Execution started.
- 2026-02-17: Step 1 completed. Inventory captured from `qm list` and `pct list`.
- 2026-02-17: Operator typo noted: `pm list` -> command not found.
- 2026-02-17: Operator requested repo-local sensitive paths (avoid `/tmp`).
- 2026-02-17: Step 2 completed. `.talosconfig` written (1700 bytes).
- 2026-02-17: Step 3 completed. Kubernetes nodes all `Ready` on Talos `v1.12.3`.
- 2026-02-17: Step 4 completed. etcd snapshot written under `runbook/events/`.
- 2026-02-17: Step 5a completed. All three Talos workers shut down cleanly.
- 2026-02-17: Step 5b completed. Talos control plane and Debian container stopped cleanly.
- 2026-02-17: Operator considered host package updates but proceeded with reboot.
- 2026-02-17: Step 6 completed. Host rebooted and SSH access restored.
- 2026-02-17: Step 7 completed. Talos VMs auto-started on host boot before manual start commands.
- 2026-02-17: Step 8 checks run. Nodes/Talos/Traefik healthy; Argo CD controller/repo-server unstable.
- 2026-02-17: Argo CD recovery script executed; all Argo CD pods returned `1/1 Running`.

## Step Log

### 1. Preconditions check

- Status: Completed
- Command(s):
  - `qm list`
  - `pct list`
- Notes:
  - VMs running initially:
    - `18591 talos-control-1`
    - `57056 talos-work-2`
    - `59770 talos-work-3`
    - `88389 talos-work-1`
  - Containers running initially:
    - `14961 debian-13-stable`
  - Attempted `pm list` (typo), shell returned `command not found`.

### 2. Talos config check

- Status: Completed
- Command(s):
  - `terraform -chdir=terraform/lab output -raw talosconfig > .talosconfig`
  - `wc -c .talosconfig`
- Notes:
  - Output size: `1700` bytes.

### 3. Kubeconfig and node readiness

- Status: Completed
- Command(s):
  - `KUBECONFIG=.kubeconfig kubectl get nodes -o wide`
- Notes:
  - All nodes `Ready` on Talos `v1.12.3`.

### 4. etcd snapshot

- Status: Completed
- Command(s):
  - `talosctl --talosconfig .talosconfig --nodes 10.4.1.215 etcd snapshot runbook/events/etcd-$(date +%F-%H%M).db`
- Notes:
  - Snapshot file: `runbook/events/etcd-2026-02-17-1853.db`
  - Reported size: `19382304` bytes
  - Snapshot info: hash `be851dbd`, revision `6846194`, total keys `808`, total size `19382272`

### 5. VM/container shutdown

- Status: Completed
- Command(s):
  - `qm shutdown 88389 --timeout 180`
  - `qm shutdown 57056 --timeout 180`
  - `qm shutdown 59770 --timeout 180`
  - `qm shutdown 18591 --timeout 180`
  - `pct shutdown 14961`
- Notes:
  - Workers, then control-plane, then container stopped cleanly.

### 6. Host reboot

- Status: Completed
- Command(s):
  - `reboot`
  - `hostname`
  - `uptime`
  - `qm list`
  - `pct list`
- Notes:
  - SSH dropped as expected during reboot (`Connection reset by peer` / `Broken pipe`).
  - Host returned successfully (`hostname: sol`, uptime ~0 min when checked).

### 7. Startup sequence

- Status: Completed
- Command(s):
  - `qm start 18591`
  - `sleep 20`
  - `qm start 88389`
  - `qm start 57056`
  - `qm start 59770`
  - `qm list`
- Notes:
  - Each `qm start` returned `already running`.
  - Talos VMs auto-started on host boot.
  - `pct 14961` was also auto-started.

### 8. Post-reboot validation

- Status: Completed (with remediation)
- Command(s):
  - `KUBECONFIG=.kubeconfig kubectl get nodes -o wide`
  - `talosctl --talosconfig .talosconfig --nodes 10.4.1.215 health`
  - `KUBECONFIG=.kubeconfig kubectl -n traefik-talos get pods,svc -o wide`
  - `KUBECONFIG=.kubeconfig kubectl -n argocd get pods -o wide`
  - `KUBECONFIG=.kubeconfig kubectl -n argocd describe pod argocd-application-controller-0`
  - `KUBECONFIG=.kubeconfig kubectl -n argocd logs argocd-application-controller-0 --previous --tail=80`
  - `bash runbook/events/argocd-recovery-2026-02-17.sh`
- Notes:
  - Initial validation:
    - Nodes all `Ready`
    - Talos health checks all `OK`
    - Traefik healthy
    - Argo CD had `CrashLoopBackOff` on app controller/repo-server and restarts on server/dex/notifications.
  - Recovery actions:
    - Restarted Argo deploys (`repo-server`, `server`, `dex`, `notifications`, `applicationset`)
    - Deleted `argocd-application-controller-0`
  - Final state:
    - All Argo CD pods `1/1 Running`.

## Artifacts

- Snapshot: `runbook/events/etcd-2026-02-17-1853.db`
- Recovery script: `runbook/events/argocd-recovery-2026-02-17.sh`

## Suggested Runbook Updates

1. Record that Talos VMs may auto-start after host reboot; startup step should include a conditional check (`qm list`) before issuing `qm start`.
2. Add Argo CD post-reboot convergence/recovery subsection:
   - Wait/recheck loop for `argocd` pods.
   - If controller/repo-server crashloop, perform rollout restart of Argo deploys and recreate `argocd-application-controller-0`.
3. Add note to avoid multiline command wrapping in interactive shells for long kubectl commands.

## Follow-up Notes (2026-02-18)

- Cluster state check after first worker reboot:
  - `talos-65n-umt` (`10.4.1.207`) `Ready`
  - `talos-e2k-9xj` (`10.4.1.189`) `NotReady`
  - `talos-lee-uq1` / `talos-thv-ld7` `Ready`
- Correlated Proxmox VM mapping from Terraform state:
  - VM `57056` -> `10.4.1.207`
  - VM `88389` -> `10.4.1.189`
- Step result: worker VM `57056` rebooted and recovered.
- Next action in sequence: reboot VM `88389` and re-run post-reboot checks.
- 2026-02-18: Worker VM `88389` reboot in progress; observed full shutdown and startup sequence initiated.
- 2026-02-18: During VM `88389` reboot, shutdown escalation observed: guest did not terminate on TERM within timeout, Proxmox proceeded with forced kill before restart.
- 2026-02-18: Post-reboot remediation: deleted `argocd-application-controller-0` and crashlooping promtail pod (`observability-promtail-92fmt`) to force clean recreation.
- 2026-02-18: Verification after recreation: `argocd-application-controller-0` and replacement promtail pod (`observability-promtail-zs9fh`) reached `1/1 Running` with `0` restarts.
- 2026-02-18: Argo applications converged to healthy except `forgejo` (`Progressing`).
- 2026-02-18: Final validation: all Argo CD applications `Synced/Healthy` (`forgejo`, `observability-*`, `storage-*`, `talos-gitops`).
- 2026-02-18: Proxmox reboot + Talos post-reboot recovery considered complete.
