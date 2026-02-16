# Proxmox Host Reboot Runbook (`sol`)

## Scope And Impact

This lab currently runs all Talos VMs on one Proxmox host (`sol`) with a single control-plane node.

Rebooting `sol` causes a planned full Kubernetes outage during the host reboot window.

## Current Known VM/CT IDs

- Talos control plane: `18591`
- Talos worker 1: `88389`
- Talos worker 2: `57056`
- Talos worker 3: `59770`
- Debian 13 container: `14961` (optional to stop/start with the window)

Verify before use:

```sh
qm list
pct list
```

## Preconditions

1. Schedule a maintenance window.
2. Confirm you have Proxmox console access after reboot.
3. Ensure Talos config exists:
   ```sh
   terraform -chdir=terraform/lab output -raw talosconfig > /tmp/talosconfig
   ```
4. Ensure kubeconfig exists:
   ```sh
   KUBECONFIG=.kubeconfig kubectl get nodes -o wide
   ```

## Procedure

1. Take an etcd snapshot from the control-plane node:
   ```sh
   talosctl --talosconfig /tmp/talosconfig --nodes 10.4.1.215 etcd snapshot /tmp/etcd-$(date +%F-%H%M).db
   ```

2. Optional pre-checks:
   ```sh
   KUBECONFIG=.kubeconfig kubectl get nodes -o wide
   KUBECONFIG=.kubeconfig kubectl -n traefik-talos get pods,svc -o wide
   KUBECONFIG=.kubeconfig kubectl -n argocd get pods -o wide
   ```

3. Shut down worker VMs first:
   ```sh
   qm shutdown 88389 --timeout 180
   qm shutdown 57056 --timeout 180
   qm shutdown 59770 --timeout 180
   ```

4. Shut down control plane last:
   ```sh
   qm shutdown 18591 --timeout 180
   ```

5. Optional: shut down Debian 13 container:
   ```sh
   pct shutdown 14961
   ```

6. Confirm they are stopped:
   ```sh
   qm list
   pct list
   ```

7. Reboot Proxmox host:
   ```sh
   reboot
   ```

## Startup Sequence After Host Returns

1. Start control plane first:
   ```sh
   qm start 18591
   ```

2. Wait a short period, then start workers:
   ```sh
   sleep 20
   qm start 88389
   qm start 57056
   qm start 59770
   ```

3. Optional: start Debian 13 container:
   ```sh
   pct start 14961
   ```

## Post-Reboot Verification

1. Confirm Kubernetes nodes return:
   ```sh
   KUBECONFIG=.kubeconfig kubectl get nodes -o wide
   ```

2. Confirm Talos control plane health:
   ```sh
   talosctl --talosconfig /tmp/talosconfig --nodes 10.4.1.215 health
   ```

3. Confirm ingress and GitOps control plane:
   ```sh
   KUBECONFIG=.kubeconfig kubectl -n traefik-talos get pods,svc -o wide
   KUBECONFIG=.kubeconfig kubectl -n argocd get pods -o wide
   ```

## If A VM Hangs During Shutdown

1. Give graceful shutdown time to complete.
2. If still running and maintenance window requires progress:
   ```sh
   qm stop <vmid>
   ```

Use forced stop only when needed.

