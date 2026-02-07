## Lab Terraform notes

- MetalLB address pool reserved: 10.4.1.88/29 (10.4.1.88-10.4.1.95)
- MetalLB upstream manifests live in `terraform/lab/metallb/manifests` for easier reading.
- GitOps manifests live in `terraform/lab/gitops/stack` (Traefik, whoami, dashboard, Argo CD ingress).
- See `terraform/lab/OVERVIEW.md` for a full walkthrough and GitOps notes.
