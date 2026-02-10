# Lab Repo Guide (AGENTS)

This repo provisions a Proxmox-based Talos Kubernetes cluster with Terraform,
then layers Kubernetes add-ons and a GitOps stack (Argo CD + Traefik + apps).

## High-level layout

- `terraform/lab/` is the main Terraform root.
- `terraform/lab/metallb/manifests/` contains the direct (non-GitOps)
  Kubernetes manifests applied by Terraform for MetalLB.
- `terraform/lab/argocd/` contains the upstream Argo CD install manifest.
- `terraform/lab/gitops/stack/` contains the GitOps-managed stack that Argo CD
  syncs (Traefik, whoami, Argo CD ingress, etc.).

## Current setup (as of today)

- Base cluster uses MetalLB for LoadBalancer IPs.
- Base (non-GitOps) resources managed by Terraform are MetalLB + Argo CD.
- GitOps stack uses Traefik (`traefik-talos`) and serves:
  - `whoami.talos.alcachofa.faith`
  - `dashboard.talos.alcachofa.faith`
  - `git.talos.alcachofa.faith` (Forgejo HTTP UI)
- Traefik also exposes Forgejo SSH on:
  - `git.talos.alcachofa.faith:22`
- Argo CD UI is exposed via GitOps Traefik at:
  - `https://argo.talos.alcachofa.faith`
- Observability is GitOps-managed in namespace `observability-talos`:
  - `kube-prometheus-stack` (Prometheus, Alertmanager, Grafana)
  - `loki` + `promtail`
  - Grafana URL: `https://grafana.talos.alcachofa.faith`
  - Preloaded dashboards:
    - `Talos Cluster Overview`
    - `Talos Workloads Health`
- Forgejo is GitOps-managed in namespace `forgejo-talos`:
  - chart source: `oci://code.forgejo.org/forgejo-helm/forgejo`
  - uses embedded SQLite on persistent volume
  - app PVC uses `forgejo-nfs`

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
- Durable app storage for Forgejo uses NFS dynamic provisioning:
  - namespace: `storage-talos`
  - app manifest: `terraform/lab/gitops/stack/26-app-nfs-subdir-provisioner.yaml`
  - StorageClass: `forgejo-nfs`
  - current configured NFS endpoint:
    - server: `10.4.1.32`
    - path: `/srv/k8s/forgejo-nfs`

Important:
- The NFS export must exist on the Proxmox host before sync.
- Recommended backing for `/srv/k8s/forgejo-nfs` is a host-backed durable
  filesystem/LVM volume, so data survives Talos VM recreation.

## Rebuild checklist

If you tear the cluster down and rebuild:

1. Run Terraform to recreate Argo CD + the Application:
   ```sh
   terraform -chdir=terraform/lab apply
   ```
2. Ensure Proxmox NFS export (`10.4.1.32:/srv/k8s/forgejo-nfs`) exists.
3. Re-seal all app credentials (SealedSecrets are cluster-specific):
  - Cloudflare token
  - Forgejo admin credentials
4. Expect Traefik to re-issue certs (local-path volumes are node-local).

## DNS prerequisites (for HTTPS routes)

Create DNS records that point to the Traefik LB IP (`10.4.1.89`) for:

- `whoami.talos.alcachofa.faith`
- `dashboard.talos.alcachofa.faith`
- `argo.talos.alcachofa.faith`
- `grafana.talos.alcachofa.faith`
- `git.talos.alcachofa.faith`

If a hostname is missing in DNS, the origin may still work by IP+SNI, but the
public hostname may fail at the edge.

For Forgejo SSH, clients connect to:
- `git.talos.alcachofa.faith:22`

## Replace the Cloudflare token (SealedSecrets)

1. Put the new token in `CFTOK` (ignored by git):
   ```sh
   echo "your_token_here" > CFTOK
   ```
2. Re-seal and overwrite the SealedSecret:
   ```sh
   TOKEN=$(tr -d '\n' < CFTOK)
   KUBECONFIG=/tmp/kubeconfig kubectl -n traefik-talos create secret generic cf-api-token \
     --from-literal=CF_DNS_API_TOKEN="$TOKEN" \
     --dry-run=client -o yaml | \
     KUBECONFIG=/tmp/kubeconfig kubeseal \
       --controller-namespace kube-system \
       --controller-name sealed-secrets-controller \
       --format yaml > terraform/lab/gitops/stack/15-sealedsecret-cf-api-token.yaml
   ```
3. Commit + push the updated SealedSecret:
   ```sh
   git add terraform/lab/gitops/stack/15-sealedsecret-cf-api-token.yaml
   git commit -m "Update sealed Cloudflare DNS token"
   git push
   ```
4. Restart Traefik to pick up the new secret (optional but fast):
   ```sh
   KUBECONFIG=/tmp/kubeconfig kubectl -n traefik-talos rollout restart deploy/traefik
   ```

## Replace Forgejo admin credentials (SealedSecrets)

1. Put admin credentials in files (ignored by git):
   ```sh
   echo "forgejo-admin" > FORGEJO_ADMIN_USER
   echo "strong_password_here" > FORGEJO_ADMIN_PASS
   echo "admin@alcachofa.faith" > FORGEJO_ADMIN_EMAIL
   ```
2. Re-seal and overwrite the SealedSecret:
   ```sh
   USER=$(tr -d '\n' < FORGEJO_ADMIN_USER)
   PASS=$(tr -d '\n' < FORGEJO_ADMIN_PASS)
   EMAIL=$(tr -d '\n' < FORGEJO_ADMIN_EMAIL)
   KUBECONFIG=/tmp/kubeconfig kubectl -n forgejo-talos create secret generic forgejo-admin-credentials \
     --from-literal=username="$USER" \
     --from-literal=password="$PASS" \
     --from-literal=email="$EMAIL" \
     --dry-run=client -o yaml | \
     KUBECONFIG=/tmp/kubeconfig kubeseal \
       --controller-namespace kube-system \
       --controller-name sealed-secrets-controller \
       --format yaml > terraform/lab/gitops/stack/29-sealedsecret-forgejo-admin.yaml
   ```

## Grafana access

- URL: `https://grafana.talos.alcachofa.faith`
- Initial credentials (chart default in this repo):
  - username: `admin`
  - password: `prom-operator`

## Traefik TLS troubleshooting

If certificates fall back to `TRAEFIK DEFAULT CERT`, check:

1. Traefik logs:
   ```sh
   KUBECONFIG=/tmp/kubeconfig kubectl -n traefik-talos logs deploy/traefik --tail=200 | rg -n 'acme|resolver|permission|default certificate'
   ```
2. ACME file is present and readable:
   ```sh
   KUBECONFIG=/tmp/kubeconfig kubectl -n traefik-talos exec deploy/traefik -- ls -l /data/acme.json
   ```
3. Cloudflare token secret exists:
   ```sh
   KUBECONFIG=/tmp/kubeconfig kubectl -n traefik-talos get secret cf-api-token
   ```

Current known-good behavior for this repo:

- Traefik uses `/data/acme.json` on PVC `traefik-acme`.
- An init container creates `acme.json` with mode `600`.
- Traefik container runs as root so ACME file permissions are acceptable to
  Traefik and writable on local-path volumes.

## How to export kubeconfig from Terraform

Terraform exposes `kubeconfig` and `talosconfig` as **sensitive outputs** in
`terraform/lab/vms.tf` (from the `cluster1` module).

To write a kubeconfig file into the repo (gitignored):

```sh
./scripts/write-kubeconfig.sh
```

Then use it with kubectl:

```sh
KUBECONFIG=.kubeconfig kubectl get nodes
```

If you also need the Talos config:

```sh
terraform -chdir=terraform/lab output -raw talosconfig > /tmp/talosconfig
```

Notes:
- You must have the Terraform state present/initialized for outputs to work.
- Outputs are marked sensitive; avoid committing or sharing the files.
