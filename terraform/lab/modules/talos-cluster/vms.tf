# Talos Control Plane
module "talos_control_plane" {
  source = "../talos-vm"

  name        = "talos-control-1"
  description = "Talos Linux Control Plane"
  node_name   = var.proxmox_node_name

  iso_file_id = var.iso_file_id

  cpu_cores       = 2
  memory          = 4096 # Control plane needs more memory
  disk_size       = 20
  ipv4_addr       = var.talos_ips[0]
  default_gateway = local.default_gateway
}

# Talos Worker 1
module "talos_worker_1" {
  source = "../talos-vm"

  name        = "talos-work-1"
  description = "Talos Linux Worker Node 1"
  node_name   = var.proxmox_node_name

  iso_file_id = var.iso_file_id

  cpu_cores       = 2
  memory          = 2048
  disk_size       = 20
  ipv4_addr       = var.talos_ips[1]
  default_gateway = local.default_gateway
}

# Talos Worker 2
module "talos_worker_2" {
  source = "../talos-vm"

  name        = "talos-work-2"
  description = "Talos Linux Worker Node 2"
  node_name   = var.proxmox_node_name

  iso_file_id = var.iso_file_id

  cpu_cores       = 2
  memory          = 2048
  disk_size       = 20
  ipv4_addr       = var.talos_ips[2]
  default_gateway = local.default_gateway
}
