locals {
  metallb_manifest_dir = "${path.module}/metallb/manifests"
  metallb_namespace = one([
    for doc in split("\n---\n", trimspace(file("${local.metallb_manifest_dir}/namespace.yaml"))) :
    yamldecode(doc)
  ])
  metallb_crd_docs = flatten([
    for path in ["${local.metallb_manifest_dir}/crds.yaml"] :
    [for doc in split("\n---\n", trimspace(file(path))) : yamldecode(doc)]
  ])
  metallb_core_docs = flatten([
    for path in [
      "${local.metallb_manifest_dir}/rbac.yaml",
      "${local.metallb_manifest_dir}/configmap.yaml",
      "${local.metallb_manifest_dir}/secret.yaml",
      "${local.metallb_manifest_dir}/service.yaml",
      "${local.metallb_manifest_dir}/controller.yaml",
      "${local.metallb_manifest_dir}/speaker.yaml",
      "${local.metallb_manifest_dir}/webhook.yaml",
    ] : [for doc in split("\n---\n", trimspace(file(path))) : yamldecode(doc)]
  ])
  metallb_pool = yamldecode(<<-YAML
    apiVersion: metallb.io/v1beta1
    kind: IPAddressPool
    metadata:
      name: default-pool
      namespace: metallb-system
    spec:
      addresses:
        - 10.4.1.88-10.4.1.95
    YAML
  )
  metallb_l2 = yamldecode(<<-YAML
    apiVersion: metallb.io/v1beta1
    kind: L2Advertisement
    metadata:
      name: default-l2
      namespace: metallb-system
    spec:
      ipAddressPools:
        - default-pool
    YAML
  )
  metallb_config_docs = [local.metallb_pool, local.metallb_l2]
}

resource "kubernetes_manifest" "metallb_namespace" {
  manifest   = local.metallb_namespace
  depends_on = [module.cluster1]
}

resource "kubernetes_manifest" "metallb_crds" {
  for_each = {
    for manifest in local.metallb_crd_docs :
    format("%s/%s/%s", manifest.kind, "_cluster", manifest.metadata.name) => manifest
  }
  manifest        = each.value
  computed_fields = ["spec.conversion.webhook.clientConfig.caBundle"]
  depends_on = [kubernetes_manifest.metallb_namespace]
}

resource "kubernetes_manifest" "metallb_core" {
  for_each = {
    for manifest in local.metallb_core_docs :
    format(
      "%s/%s/%s",
      manifest.kind,
      lookup(manifest.metadata, "namespace", "_cluster"),
      manifest.metadata.name
    ) => manifest
  }
  manifest        = each.value
  computed_fields = each.value.kind == "ValidatingWebhookConfiguration" ? ["metadata.creationTimestamp"] : null
  depends_on = [kubernetes_manifest.metallb_namespace, kubernetes_manifest.metallb_crds]
}

resource "kubernetes_manifest" "metallb_config" {
  for_each   = { for idx, manifest in local.metallb_config_docs : tostring(idx) => manifest }
  manifest   = each.value
  depends_on = [kubernetes_manifest.metallb_crds, kubernetes_manifest.metallb_core]
}
