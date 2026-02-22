locals {
  kubeconfig = yamldecode(module.cluster1.kubeconfig)
}
