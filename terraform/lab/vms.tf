
module "cluster1" {
  source             = "./modules/talos-cluster"
  proxmox_node_name  = "sol"
  talos_cluster_name = "test-base"
  # Keep existing VM disk source pinned to avoid forced VM replacement.
  # Talos version upgrades for running nodes are done with talosctl rolling upgrades.
  iso_file_id = proxmox_virtual_environment_download_file.talos_nocloud_image2.id
}

output "talosconfig" {
  value     = module.cluster1.talosconfig
  sensitive = true
}
output "kubeconfig" {
  value     = module.cluster1.kubeconfig
  sensitive = true
}
