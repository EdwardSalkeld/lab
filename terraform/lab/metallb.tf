locals {
  metallb_native_docs = [
    for doc in split("\n---\n", trimspace(file("${path.module}/metallb-native.yaml"))) :
    yamldecode(doc)
  ]
  metallb_namespace = one([
    for manifest in local.metallb_native_docs : manifest
    if manifest.kind == "Namespace" && manifest.metadata.name == "metallb-system"
  ])
  metallb_crd_docs = [
    for manifest in local.metallb_native_docs : manifest
    if manifest.kind == "CustomResourceDefinition"
  ]
  metallb_core_docs = [
    for manifest in local.metallb_native_docs : manifest
    if manifest.kind != "Namespace" && manifest.kind != "CustomResourceDefinition"
  ]
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
  manifest   = each.value
  depends_on = [kubernetes_manifest.metallb_namespace, kubernetes_manifest.metallb_crds]
}

resource "kubernetes_manifest" "metallb_config" {
  for_each   = { for idx, manifest in local.metallb_config_docs : tostring(idx) => manifest }
  manifest   = each.value
  depends_on = [kubernetes_manifest.metallb_crds, kubernetes_manifest.metallb_core]
}
