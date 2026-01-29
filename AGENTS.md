# Lab Repo Guide (AGENTS)

This repo provisions a Proxmox-based Talos Kubernetes cluster with Terraform,
then layers Kubernetes add-ons and a GitOps stack (Argo CD + Traefik + whoami).

## High-level layout

- `terraform/lab/` is the main Terraform root.
- `terraform/lab/k8s/manifests/` contains the direct (non-GitOps) Kubernetes
  add-ons for the base cluster.
- `terraform/lab/argocd/` contains the upstream Argo CD install manifest.
- `terraform/lab/gitops/stack/` contains the GitOps-managed stack that Argo CD
  syncs (Traefik, whoami, Argo CD ingress, etc.).

## Current setup (as of today)

- Base cluster uses MetalLB for LoadBalancer IPs.
- Traefik (base stack) serves:
  - `whoami.k8s.alcachofa.faith`
  - `dashboard.k8s.alcachofa.faith`
- GitOps stack uses a parallel Traefik (`traefik-talos`) and serves:
  - `whoami.talos.alcachofa.faith`
  - `dashboard.talos.alcachofa.faith`
- Argo CD UI is exposed via GitOps Traefik at:
  - `https://argo.talos.alcachofa.faith`

The GitOps stack is the source of truth for the Traefik that fronts Argo CD.

## Storage (GitOps)

- Storage is provided by Rancher Local Path Provisioner.
- Manifest: `terraform/lab/gitops/stack/17-local-path-storage.yaml`
- StorageClass: `local-path` (set as default).
- PVCs are backed by a hostPath on the node:
  - path: `/opt/local-path-provisioner`
- Pod Security: `local-path-storage` namespace is labeled `privileged` to
  allow the helper pods that create hostPath volumes.
- Traefik ACME storage uses:
  - PVC `traefik-acme` in `traefik-talos`
  - StorageClass `local-path`

## How to export kubeconfig from Terraform

Terraform exposes `kubeconfig` and `talosconfig` as **sensitive outputs** in
`terraform/lab/vms.tf` (from the `cluster1` module). To write a kubeconfig file:

```sh
terraform -chdir=terraform/lab output -raw kubeconfig > /tmp/kubeconfig
```

Then use it with kubectl:

```sh
KUBECONFIG=/tmp/kubeconfig kubectl get nodes
```

If you also need the Talos config:

```sh
terraform -chdir=terraform/lab output -raw talosconfig > /tmp/talosconfig
```

Notes:
- You must have the Terraform state present/initialized for outputs to work.
- Outputs are marked sensitive; avoid committing or sharing the files.
