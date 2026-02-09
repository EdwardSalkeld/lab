## Lab Terraform notes

- MetalLB address pool reserved: 10.4.1.88/29 (10.4.1.88-10.4.1.95)
- MetalLB upstream manifests live in `terraform/lab/metallb/manifests` for easier reading.
- GitOps manifests live in `terraform/lab/gitops/stack` (Traefik, Argo CD ingress, whoami, storage, observability apps, Forgejo).
- See `terraform/lab/OVERVIEW.md` for a full walkthrough and GitOps notes.

## Quick ops

- Apply infra and Argo app:
  - `terraform -chdir=terraform/lab apply`
- Switch Argo tracked branch:
  - `source terraform/lab/.env && TF_VAR_ARGOCD_REPO_REVISION=main terraform -chdir=terraform/lab apply -auto-approve`
- Export kubeconfig:
  - `./scripts/write-kubeconfig.sh`
  - `KUBECONFIG=.kubeconfig kubectl get nodes`

## Endpoints (GitOps stack)

- `https://argo.talos.alcachofa.faith`
- `https://dashboard.talos.alcachofa.faith`
- `https://whoami.talos.alcachofa.faith`
- `https://grafana.talos.alcachofa.faith`
- `https://git.talos.alcachofa.faith`

All hostnames above must have DNS records pointing to the Traefik LoadBalancer IP (`10.4.1.89`).

Forgejo Git SSH is exposed on `git.talos.alcachofa.faith:22` through the same Traefik LoadBalancer IP.

Forgejo persistence uses `forgejo-nfs` StorageClass via `nfs-subdir-external-provisioner` (`10.4.1.32:/srv/k8s/forgejo-nfs`).
Forgejo uses an external in-cluster PostgreSQL (`forgejo-postgresql`) with its data PVC on `forgejo-nfs`.
