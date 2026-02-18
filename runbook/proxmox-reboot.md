# Proxmox Host Reboot Runbook (`sol`)

## Scope And Impact

This lab runs all Talos VMs on one Proxmox host (`sol`) with a single control-plane node.

Rebooting `sol` is a full Kubernetes outage. Startup must be staged to reduce post-boot churn.

## Current Known VM/CT IDs

- Talos control plane: `18591` (`talos-lee-uq1` / `10.4.1.215`)
- Talos worker 1: `88389` (`talos-e2k-9xj` / `10.4.1.189`)
- Talos worker 2: `57056` (`talos-65n-umt` / `10.4.1.207`)
- Talos worker 3: `59770` (`talos-thv-ld7` / `10.4.1.148`)
- Debian 13 container: `14961` (optional)

Verify before use:

```sh
qm list
pct list
```

## Preconditions

1. Schedule a maintenance window.
2. Confirm Proxmox console access.
3. Ensure Talos config exists (repo-local):
   ```sh
   terraform -chdir=terraform/lab output -raw talosconfig > .talosconfig
   ```
4. Ensure kubeconfig works:
   ```sh
   KUBECONFIG=.kubeconfig kubectl get nodes -o wide
   ```
5. Ensure sensitive local files are gitignored (for example: `.talosconfig`).

## Pre-Reboot Procedure

1. Take an etcd snapshot:
   ```sh
   talosctl --talosconfig .talosconfig --nodes 10.4.1.215 etcd snapshot runbook/events/etcd-$(date +%F-%H%M).db
   ```

2. Optional baseline checks:
   ```sh
   KUBECONFIG=.kubeconfig kubectl get nodes -o wide
   KUBECONFIG=.kubeconfig kubectl -n kube-system get pods -o wide | rg 'flannel|kube-proxy|metallb-speaker'
   KUBECONFIG=.kubeconfig kubectl -n argocd get applications.argoproj.io
   ```

3. Shut down workers first (longer timeout):
   ```sh
   qm shutdown 88389 --timeout 300
   qm shutdown 57056 --timeout 300
   qm shutdown 59770 --timeout 300
   ```

4. Shut down control plane last:
   ```sh
   qm shutdown 18591 --timeout 300
   ```

5. Optional: shut down Debian container:
   ```sh
   pct shutdown 14961
   ```

6. Confirm all intended guests are stopped:
   ```sh
   qm list
   pct list
   ```

7. Reboot Proxmox host:
   ```sh
   reboot
   ```

## Staged Startup Sequence

1. Reconnect and check host state:
   ```sh
   hostname
   uptime
   qm list
   pct list
   ```

2. Start control-plane VM only (if not already running):
   ```sh
   qm start 18591
   ```

3. Wait for API/control-plane readiness gate before workers:
   ```sh
   KUBECONFIG=.kubeconfig kubectl get node talos-lee-uq1 -w
   talosctl --talosconfig .talosconfig --nodes 10.4.1.215 health
   ```

4. Start workers one at a time and gate each step:
   ```sh
   qm start 57056
   KUBECONFIG=.kubeconfig kubectl get node talos-65n-umt -w

   qm start 88389
   KUBECONFIG=.kubeconfig kubectl get node talos-e2k-9xj -w

   qm start 59770
   KUBECONFIG=.kubeconfig kubectl get node talos-thv-ld7 -w
   ```

5. Optional: start Debian container if needed:
   ```sh
   pct start 14961
   ```

## Post-Reboot Verification

1. Node and system plane checks:
   ```sh
   KUBECONFIG=.kubeconfig kubectl get nodes -o wide
   KUBECONFIG=.kubeconfig kubectl -n kube-system get pods -o wide | rg 'flannel|kube-proxy|metallb-speaker'
   ```

2. Argo and app checks:
   ```sh
   KUBECONFIG=.kubeconfig kubectl -n argocd get pods -o wide
   KUBECONFIG=.kubeconfig kubectl -n argocd get applications.argoproj.io
   KUBECONFIG=.kubeconfig kubectl -n observability-talos get pods -o wide
   ```

3. Wait and recheck once (startup churn can settle):
   ```sh
   sleep 60
   KUBECONFIG=.kubeconfig kubectl -n argocd get applications.argoproj.io
   ```

## Fallback Ladder (Use In Order)

1. If only a few pods are crashlooping, recreate those pods first:
   ```sh
   KUBECONFIG=.kubeconfig kubectl -n argocd delete pod argocd-application-controller-0
   KUBECONFIG=.kubeconfig kubectl -n observability-talos delete pod <crashlooping-observability-pod>
   ```

2. If Argo control-plane pods remain unstable, restart Argo deploys then recreate controller pod:
   ```sh
   KUBECONFIG=.kubeconfig kubectl -n argocd rollout restart deploy/argocd-repo-server deploy/argocd-server deploy/argocd-dex-server deploy/argocd-notifications-controller deploy/argocd-applicationset-controller
   KUBECONFIG=.kubeconfig kubectl -n argocd delete pod argocd-application-controller-0
   ```

3. If failures are concentrated on one worker, reboot that worker VM only:
   ```sh
   # talos-65n-umt
   qm reboot 57056
   # talos-e2k-9xj
   qm reboot 88389
   # talos-thv-ld7
   qm reboot 59770
   ```

4. If root cause is unclear, collect focused diagnostics:
   ```sh
   KUBECONFIG=.kubeconfig kubectl get events -A --sort-by=.lastTimestamp | rg -i 'oom|MemoryPressure|SandboxChanged|Evict' | tail -n 100
   talosctl --talosconfig .talosconfig --nodes 10.4.1.148 logs kernel --tail 300 | rg -i 'oom|Out of memory|Killed process|Memory cgroup'
   ```

## If A VM Hangs During Shutdown

1. Keep graceful shutdown as first choice.
2. After timeout expiry, force stop only if the window requires progress:
   ```sh
   qm stop <vmid>
   ```

## Notes

- `on_boot=true` can start all VMs automatically; still use readiness gates before proceeding to application checks.
- In this lab, recent instability after host reboot correlated with Talos OOM kills on worker nodes.
- Long, single-line commands reduce interactive shell line-wrap mistakes.

## Future Capacity Option

- If post-reboot instability continues, consider switching worker topology from `3 x 2GiB` to `2 x 4GiB` on this `16GiB` host.
- Expected benefit: better per-node memory headroom and fewer OOM kills during restart churn.
- Tradeoff: reduced worker redundancy (losing one worker removes 50% of worker capacity instead of ~33%).
- Decision point: reassess after applying current QoS/resource and staged-reboot changes and running the next maintenance reboot.
