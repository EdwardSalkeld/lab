# Terraform Lab Overview

This repo provisions a Proxmox-based Talos Kubernetes cluster and then applies
cluster add-ons (MetalLB, Traefik, whoami) using the Kubernetes provider.

## Flow at a glance

1. Proxmox resources (VMs/containers, images) are created.
2. Talos config is generated and applied to bootstrap the cluster.
3. A kubeconfig is derived from Talos.
4. Kubernetes provider applies MetalLB and app manifests.
5. MetalLB allocates `10.4.1.88` for the Traefik LoadBalancer service.
6. Traefik exposes `whoami.k8s.alcachofa.faith` and `dashboard.k8s.alcachofa.faith`.
7. Argo CD can manage a parallel GitOps stack under `terraform/lab/gitops/stack`.

## Terraform files

- `terraform/lab/providers.tf` — provider config (Proxmox, Talos, Kubernetes, etc).
- `terraform/lab/variables.tf` — input variables for endpoints, tokens, and cluster settings.
- `terraform/lab/outputs.tf` — exported values (kubeconfig, talosconfig, IDs).
- `terraform/lab/images.tf` — ISO/IMG downloads used by Proxmox.
- `terraform/lab/vms.tf` — Talos VM definitions for control plane and workers.
- `terraform/lab/containers.tf` — Debian LXC containers.
- `terraform/lab/modules/` — reusable Terraform modules (Talos cluster pieces).

## Kubernetes add-ons

- `terraform/lab/kubernetes.tf` — applies Kubernetes manifests from `k8s/manifests`.
- `terraform/lab/k8s/manifests/` — ordered Kubernetes YAML:
  - `00-namespace.yaml` — `traefik` namespace.
  - `01-serviceaccount.yaml` — Traefik service account.
  - `02-clusterrole.yaml` — Traefik RBAC role.
  - `03-clusterrolebinding.yaml` — Traefik RBAC binding.
  - `04-ingressclass.yaml` — Traefik ingress class.
  - `05-traefik-deployment.yaml` — Traefik controller pod.
  - `06-traefik-service.yaml` — LoadBalancer service pinned to `10.4.1.88`.
  - `07-whoami-deployment.yaml` — whoami app.
  - `08-whoami-service.yaml` — whoami service.
  - `09-whoami-ingress.yaml` — `whoami.k8s.alcachofa.faith` routing.
  - `10-traefik-dashboard-ingress.yaml` — dashboard routing.

## GitOps (Argo CD)

- `terraform/lab/argocd.tf` — installs Argo CD from upstream manifests.
- `terraform/lab/argocd/manifests/install.yaml` — Argo CD install manifest (upstream).
- `terraform/lab/gitops/stack/` — GitOps-managed parallel stack:
  - `00-namespace-traefik.yaml` — `traefik-talos` namespace.
  - `01-namespace-apps.yaml` — `apps-talos` namespace.
  - `02-traefik-serviceaccount.yaml` — Traefik service account.
  - `03-traefik-clusterrole.yaml` — Traefik RBAC role.
  - `04-traefik-clusterrolebinding.yaml` — Traefik RBAC binding.
  - `05-traefik-ingressclass.yaml` — Traefik ingress class (`traefik-talos`).
  - `06-traefik-deployment.yaml` — Traefik controller pod.
  - `07-traefik-service.yaml` — LoadBalancer service pinned to `10.4.1.89`.
  - `08-whoami-deployment.yaml` — whoami app.
  - `09-whoami-service.yaml` — whoami service.
  - `10-whoami-ingress.yaml` — `whoami.talos.alcachofa.faith` routing.
  - `11-traefik-dashboard-ingress.yaml` — dashboard routing.

## MetalLB (LoadBalancer IPs)

- `terraform/lab/metallb.tf` — installs MetalLB and config from manifests.
- `terraform/lab/metallb/manifests/` — upstream MetalLB YAML split by component:
  - `namespace.yaml`, `crds.yaml`, `rbac.yaml`
  - `controller.yaml`, `speaker.yaml`
  - `service.yaml`, `webhook.yaml`, `secret.yaml`
  - `configmap.yaml`
- `terraform/lab/metallb_config` resources — define the IP address pool
  (`10.4.1.88/29`) and L2 advertisement.

## Notes

- DNS should point `whoami.k8s.alcachofa.faith` and
  `dashboard.k8s.alcachofa.faith` to `10.4.1.88`.
- GitOps parallel stack uses `10.4.1.89` and `*.talos.alcachofa.faith`.
- If the Git repo is private, set Argo CD repo credentials via
  `ARGOCD_REPO_SSH_PRIVATE_KEY` or `ARGOCD_REPO_USERNAME`/`ARGOCD_REPO_PASSWORD`.
- TLS is intentionally not configured yet.
