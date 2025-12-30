resource "talos_machine_secrets" "machine_secrets" {
}

locals {
  endpoint_ip = module.talos_control_plane.ip
  worker_ips = [
    module.talos_worker_1.ip,
    module.talos_worker_2.ip,
    module.talos_worker_3.ip,
  ]
  all_ips = flatten([[module.talos_control_plane.ip], local.worker_ips])

}
data "talos_client_configuration" "talosconfig" {
  cluster_name         = var.talos_cluster_name
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  endpoints            = [module.talos_control_plane.ip]
  nodes                = local.all_ips
}
output "tst" {
  value = module.talos_control_plane.ip
}

data "talos_machine_configuration" "machineconfig_cp" {
  cluster_name     = var.talos_cluster_name
  cluster_endpoint = "https://${local.endpoint_ip}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.machine_secrets.machine_secrets
}

resource "talos_machine_configuration_apply" "cp_config_apply" {
  depends_on                  = [module.talos_control_plane.vm]
  client_configuration        = talos_machine_secrets.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_cp.machine_configuration
  node                        = local.endpoint_ip
}

data "talos_machine_configuration" "machineconfig_worker" {
  cluster_name     = var.talos_cluster_name
  cluster_endpoint = "https://${local.endpoint_ip}:6443"
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.machine_secrets.machine_secrets
}

resource "talos_machine_configuration_apply" "worker1_config_apply" {
  depends_on                  = [module.talos_worker_1.vm]
  client_configuration        = talos_machine_secrets.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_worker.machine_configuration
  node                        = module.talos_worker_1.ip
}
resource "talos_machine_configuration_apply" "worker2_config_apply" {
  depends_on                  = [module.talos_worker_2.vm]
  client_configuration        = talos_machine_secrets.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_worker.machine_configuration
  node                        = module.talos_worker_2.ip
}
resource "talos_machine_configuration_apply" "worker3_config_apply" {
  depends_on                  = [module.talos_worker_3.vm]
  client_configuration        = talos_machine_secrets.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_worker.machine_configuration
  node                        = module.talos_worker_3.ip
}

resource "talos_machine_bootstrap" "bootstrap" {
  # depends_on           = [talos_machine_configuration_apply.cp_config_apply]
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = local.endpoint_ip
}

data "talos_cluster_health" "health" {
  depends_on           = [talos_machine_configuration_apply.cp_config_apply, talos_machine_configuration_apply.worker1_config_apply, talos_machine_configuration_apply.worker2_config_apply]
  client_configuration = data.talos_client_configuration.talosconfig.client_configuration
  control_plane_nodes  = [local.endpoint_ip]
  worker_nodes         = local.worker_ips
  endpoints            = [local.endpoint_ip]
}

resource "talos_cluster_kubeconfig" "kubeconfig" {
  depends_on           = [talos_machine_bootstrap.bootstrap, data.talos_cluster_health.health]
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = local.endpoint_ip
}

output "talosconfig" {
  value     = data.talos_client_configuration.talosconfig.talos_config
  sensitive = true
}

output "kubeconfig" {
  value     = talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw
  sensitive = true
}
