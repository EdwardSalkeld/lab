
module "cluster" {
  source            = "./modules/talos-cluster"
  proxmox_node_name = "sol"
  iso_file_id       = proxmox_virtual_environment_download_file.talos_nocloud_image2.id
}

output "talosconfig" {
  value     = module.cluster.talosconfig
  sensitive = true
}

output "vmc" {
  value = module.cluster.vmc
}
