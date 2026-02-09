# Terraform Lab Overview

This repo provisions a Proxmox-based Talos Kubernetes cluster and then applies
cluster add-ons (MetalLB, Argo CD) using the Kubernetes provider.

## Flow at a glance

1. Proxmox resources (VMs/containers, images) are created.
2. Talos config is generated and applied to bootstrap the cluster.
3. A kubeconfig is derived from Talos.
4. Kubernetes provider applies MetalLB and Argo CD.
5. Argo CD manages the GitOps stack under `terraform/lab/gitops/stack`.

## Terraform files

- `terraform/lab/providers.tf` — provider config (Proxmox, Talos, Kubernetes, etc).
- `terraform/lab/variables.tf` — input variables for endpoints, tokens, and cluster settings.
- `terraform/lab/outputs.tf` — exported values (kubeconfig, talosconfig, IDs).
- `terraform/lab/images.tf` — ISO/IMG downloads used by Proxmox.
- `terraform/lab/vms.tf` — Talos VM definitions for control plane and workers.
- `terraform/lab/containers.tf` — Debian LXC containers.
- `terraform/lab/modules/` — reusable Terraform modules (Talos cluster pieces).

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
  - `12-argocd-ingress.yaml` — `argo.talos.alcachofa.faith` routing.
  - `13-argocd-cmd-params.yaml` — Argo CD server CLI params (`server.insecure`).
  - `14-sealed-secrets-controller.yaml` — Sealed Secrets controller.
  - `15-sealedsecret-cf-api-token.yaml` — Sealed Cloudflare token for Traefik DNS-01.
  - `16-traefik-acme-pvc.yaml` — Traefik ACME PVC (`local-path`).
  - `17-local-path-storage.yaml` — Local Path Provisioner + default StorageClass.
  - `18-namespace-observability.yaml` — `observability-talos` namespace.
  - `19-app-kube-prometheus-stack.yaml` — Argo CD app for metrics + Grafana.
  - `20-app-loki.yaml` — Argo CD app for Loki log storage.
  - `21-app-promtail.yaml` — Argo CD app for Promtail log shipping.
  - `22-grafana-dashboard-cluster-overview.yaml` — Grafana dashboard ConfigMap.
  - `23-grafana-dashboard-workloads.yaml` — Grafana dashboard ConfigMap.

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

- GitOps stack uses `10.4.1.89` and `*.talos.alcachofa.faith`.
- Grafana is exposed via `grafana.talos.alcachofa.faith`.
- DNS records must exist for each hostname (`argo`, `dashboard`, `whoami`,
  `grafana`) and resolve to the Traefik LB endpoint.
- If the Git repo is private, set Argo CD repo credentials via
  `ARGOCD_REPO_SSH_PRIVATE_KEY` or `ARGOCD_REPO_USERNAME`/`ARGOCD_REPO_PASSWORD`.
- TLS is configured via Traefik + Let's Encrypt (Cloudflare DNS-01).
- Grafana default login in this setup: `admin` / `prom-operator`.
- If Traefik serves `TRAEFIK DEFAULT CERT`, inspect Traefik logs for ACME
  resolver errors and verify `/data/acme.json` exists on the `traefik-acme` PVC.
