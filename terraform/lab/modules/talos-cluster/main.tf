resource "talos_machine_secrets" "machine_secrets" {
}
data "talos_client_configuration" "talosconfig" {
  cluster_name         = var.talos_cluster_name
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  endpoints            = [var.talos_ips[0]]
  nodes                = var.talos_ips
}

data "talos_machine_configuration" "machineconfig_cp" {
  cluster_name     = var.talos_cluster_name
  cluster_endpoint = "https://${var.talos_ips[0]}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.machine_secrets.machine_secrets
}

# resource "talos_machine_configuration_apply" "cp_config_apply" {
#   depends_on                  = [module.talos_control_plane.vm]
#   client_configuration        = talos_machine_secrets.machine_secrets.client_configuration
#   machine_configuration_input = data.talos_machine_configuration.machineconfig_cp.machine_configuration
#   node                        = var.talos_ips[0]
# }
#
# data "talos_machine_configuration" "machineconfig_worker1" {
#   cluster_name     = var.talos_cluster_name
#   cluster_endpoint = "https://${var.talos_ips[0]}:6443"
#   machine_type     = "worker"
#   machine_secrets  = talos_machine_secrets.machine_secrets.machine_secrets
# }
#
# data "talos_machine_configuration" "machineconfig_worker2" {
#   cluster_name     = var.talos_cluster_name
#   cluster_endpoint = "https://${var.talos_ips[0]}:6443"
#   machine_type     = "worker"
#   machine_secrets  = talos_machine_secrets.machine_secrets.machine_secrets
# }
#
# resource "talos_machine_configuration_apply" "worker1_config_apply" {
#   depends_on                  = [module.talos_worker_1.vm]
#   client_configuration        = talos_machine_secrets.machine_secrets.client_configuration
#   machine_configuration_input = data.talos_machine_configuration.machineconfig_worker1.machine_configuration
#   node                        = var.talos_ips[1]
# }
# resource "talos_machine_configuration_apply" "worker2_config_apply" {
#   depends_on                  = [module.talos_worker_2.vm]
#   client_configuration        = talos_machine_secrets.machine_secrets.client_configuration
#   machine_configuration_input = data.talos_machine_configuration.machineconfig_worker2.machine_configuration
#   node                        = var.talos_ips[2]
# }
#
# resource "talos_machine_bootstrap" "bootstrap" {
#   depends_on           = [talos_machine_configuration_apply.cp_config_apply]
#   client_configuration = talos_machine_secrets.machine_secrets.client_configuration
#   node                 = var.talos_ips[0]
# }

# data "talos_cluster_health" "health" {
#   depends_on           = [talos_machine_configuration_apply.cp_config_apply, talos_machine_configuration_apply.worker1_config_apply, talos_machine_configuration_apply.worker2_config_apply]
#   client_configuration = data.talos_client_configuration.talosconfig.client_configuration
#   control_plane_nodes  = [var.talos_ips[0]]
#   worker_nodes         = [var.talos_ips[1], var.talos_ips[2]]
#   endpoints            = [var.talos_ips[0]]
# }

# resource "talos_cluster_kubeconfig" "kubeconfig" {
#   depends_on           = [talos_machine_bootstrap.bootstrap, data.talos_cluster_health.health]
#   client_configuration = talos_machine_secrets.machine_secrets.client_configuration
#   node                 = var.talos_ips[0]
# }

output "talosconfig" {
  value     = data.talos_client_configuration.talosconfig.talos_config
  sensitive = true
}

# output "kubeconfig" {
#   value     = talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw
#   sensitive = true
# }
