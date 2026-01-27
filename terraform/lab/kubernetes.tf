locals {
  kubeconfig = yamldecode(module.cluster1.kubeconfig)
  k8s_manifest_dir = "${path.module}/k8s/manifests"
  k8s_manifest_files = sort(fileset(local.k8s_manifest_dir, "*.yaml"))
  k8s_manifests = [for file in local.k8s_manifest_files : yamldecode(file("${local.k8s_manifest_dir}/${file}"))]
  traefik_namespace = one([
    for manifest in local.k8s_manifests : manifest
    if manifest.kind == "Namespace" && manifest.metadata.name == "traefik"
  ])
  k8s_other_manifests = [
    for manifest in local.k8s_manifests : manifest
    if !(manifest.kind == "Namespace" && manifest.metadata.name == "traefik")
  ]
}

resource "kubernetes_manifest" "traefik_namespace" {
  manifest   = local.traefik_namespace
  depends_on = [module.cluster1]
}

resource "kubernetes_manifest" "k8s" {
  for_each = {
    for manifest in local.k8s_other_manifests :
    format(
      "%s/%s/%s",
      manifest.kind,
      lookup(manifest.metadata, "namespace", "_cluster"),
      manifest.metadata.name
    ) => manifest
  }
  manifest   = each.value
  depends_on = [kubernetes_manifest.traefik_namespace]
}
