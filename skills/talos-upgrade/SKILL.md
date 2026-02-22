---
name: talos-upgrade
description: Plan and execute rolling Talos Linux upgrades for this Proxmox + Terraform lab cluster. Use when asked to upgrade Talos nodes, choose a safe version path, manage Image Factory schematics/images, perform one-node-at-a-time talosctl upgrades, and align Terraform to the upgraded version.
---

# Talos Upgrade (Lab Runbook)

Use this runbook for this repo's Talos cluster (1 control plane + 3 workers).

## Preflight

1. Ensure kubeconfig exists:
   ```sh
   KUBECONFIG=.kubeconfig kubectl get nodes -o wide
   ```
2. Export Talos config from Terraform state:
   ```sh
   terraform -chdir=terraform output -raw talosconfig > /tmp/talosconfig
   ```
3. Verify node health before any upgrade:
   ```sh
   talosctl --talosconfig /tmp/talosconfig --nodes <node-ip> health
   KUBECONFIG=.kubeconfig kubectl get nodes -o wide
   ```

Only proceed when all nodes are `Ready`.

## Choose Upgrade Path

1. Follow patch-first/minor-second progression.
2. If crossing minors, upgrade to latest patch in current minor first, then target minor.
3. Confirm versions available from factory when needed:
   ```sh
   curl -s https://factory.talos.dev/versions | jq -r '.[]'
   ```

## Prepare Image/Schematic in Terraform

1. Keep a Terraform-managed schematic for required extensions (qemu guest agent).
2. Keep Terraform download resources for the target Talos installer/raw image.
3. Apply image/schematic resources before manual rollout so assets exist in Proxmox.
4. Do not immediately repoint VM source image for existing machines; perform manual rolling upgrade first.

## Rolling Upgrade Procedure

Run upgrades serially. Never run two node upgrades in parallel.

Order:
1. Worker 1
2. Worker 2
3. Worker 3
4. Control plane (last)

Use long timeouts and single-attempt execution:

```sh
talosctl \
  --talosconfig /tmp/talosconfig \
  --endpoints <control-plane-ip> \
  --nodes <node-ip> \
  upgrade \
  --image factory.talos.dev/installer/<schematic-id>:<target-version> \
  --wait \
  --timeout 60m
```

Expected watcher progression:
- `waiting for actor ID`
- `task: cordonAndDrainNode action: START`
- `task: stopAllPods action: START`
- `unavailable, retrying...`
- `post check passed`

Wait patiently; do not re-trigger just because it is slow.

## Per-Node Verification

After each node:

```sh
KUBECONFIG=.kubeconfig kubectl get node <node-name> -o wide
talosctl --talosconfig /tmp/talosconfig --nodes <node-ip> version
```

Proceed only after node is `Ready` and on target Talos version.

## Post-Rollout Verification

1. Confirm all nodes upgraded:
   ```sh
   KUBECONFIG=.kubeconfig kubectl get nodes -o wide
   talosctl --talosconfig /tmp/talosconfig --nodes <ip1>,<ip2>,<ip3>,<ip4> version
   ```
2. Validate critical services:
   ```sh
   KUBECONFIG=.kubeconfig kubectl -n traefik-talos get pods,svc -o wide
   KUBECONFIG=.kubeconfig kubectl -n argocd get pods -o wide
   ```

## Troubleshooting

- `waiting for actor ID` for a long time can still be normal; avoid duplicate upgrade commands.
- If a repeated command reports `upgrade failed: locked`, an upgrade is already in progress.
- If node flaps `NotReady`, wait first; if it does not recover, use:
  ```sh
  talosctl reboot --talosconfig /tmp/talosconfig --nodes <node-ip>
  ```
- Ingress/UI instability during worker churn can happen; prioritize finishing controlled rollout unless there is a hard outage.

## Terraform Reconciliation After Manual Upgrade

After all nodes are upgraded:

1. Set upgrade version variables/resources in `terraform/images.tf` to the target version.
2. Repoint `terraform/vms.tf` (`iso_file_id`) to the target image resource.
3. Run:
   ```sh
   terraform -chdir=terraform validate
   terraform -chdir=terraform plan
   ```
4. Apply if plan is as expected.
