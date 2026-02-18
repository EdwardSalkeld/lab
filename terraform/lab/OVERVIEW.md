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
  - `22-grafana-dashboard-cluster-overview.yaml` — Grafana dashboard ConfigMap.
  - `23-grafana-dashboard-workloads.yaml` — Grafana dashboard ConfigMap.
  - `24-traefik-tcp-config.yaml` — Traefik file-provider TCP route config (Forgejo SSH).
  - `25-namespace-storage.yaml` — `storage-talos` namespace.
  - `26-app-nfs-subdir-provisioner.yaml` — Argo CD app for NFS dynamic provisioning.
  - `27-namespace-forgejo.yaml` — `forgejo-talos` namespace.
  - `28-app-forgejo.yaml` — Argo CD app for Forgejo (SQLite on persistent volume).
  - `29-sealedsecret-forgejo-admin.yaml` — Sealed Forgejo admin credentials.
  - `30-namespace-vaultwarden.yaml` — `vaultwarden-talos` namespace.
  - `31-sealedsecret-vaultwarden-admin-token.yaml` — Sealed VaultWarden admin token.
  - `32-vaultwarden-pvc.yaml` — VaultWarden PVC on `forgejo-nfs` (`5Gi`).
  - `33-vaultwarden-deployment.yaml` — VaultWarden deployment (single-user settings).
  - `34-vaultwarden-service.yaml` — VaultWarden ClusterIP service.
  - `35-vaultwarden-ingress.yaml` — `vault.talos.alcachofa.faith` ingress via Traefik.

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
- Forgejo is exposed via `git.talos.alcachofa.faith` (HTTPS + SSH on port 22).
- VaultWarden is exposed via `vault.talos.alcachofa.faith`.
- DNS records must exist for each hostname (`argo`, `dashboard`, `whoami`,
  `grafana`, `git`, `vault`) and resolve to the Traefik LB endpoint.
- If the Git repo is private, set Argo CD repo credentials via
  `ARGOCD_REPO_SSH_PRIVATE_KEY` or `ARGOCD_REPO_USERNAME`/`ARGOCD_REPO_PASSWORD`.
- TLS is configured via Traefik + Let's Encrypt (Cloudflare DNS-01).
- Forgejo data is configured to use `forgejo-nfs` StorageClass (backed by
  `nfs-subdir-external-provisioner`).
- VaultWarden data is configured to use `forgejo-nfs` StorageClass.
- VaultWarden is operated as a manual one-way mirror target from Bitwarden
  cloud exports.
- VaultWarden registration and invitations are disabled in steady state (no SMTP flow required).
- Grafana default login in this setup: `admin` / `prom-operator`.
- If Traefik serves `TRAEFIK DEFAULT CERT`, inspect Traefik logs for ACME
  resolver errors and verify `/data/acme.json` exists on the `traefik-acme` PVC.
