
module "cluster" {
  source            = "./modules/talos-cluster"
  proxmox_node_name = "sol"
  iso_file_id       = proxmox_virtual_environment_download_file.talos_nocloud_image2.id
}

output "talosconfig" {
  value     = module.cluster.talosconfig
  sensitive = true
}
output "kubeconfig" {
  value     = module.cluster.kubeconfig
  sensitive = true
}
# output "tst" {
#   value = module.cluster.tst
# }

# output "vmc" {
#   value = module.cluster.vmc
# }

# locals {
#   all_ips          = compact(flatten(module.cluster.vmc.ipv4_addresses))
#   non_loopback_ips = [for ip in local.all_ips : ip if ip != "127.0.0.1"]
#   first_real_ip    = element(local.non_loopback_ips, 0)
#
# }
# output "vmc_ip" {
#   value = local.first_real_ip
# }
