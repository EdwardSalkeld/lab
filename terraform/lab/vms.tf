# Talos Control Plane
module "talos_control_plane" {
  source = "../modules/talos-vm"

  name        = "talos-control-1"
  description = "Talos Linux Control Plane"
  node_name   = "pve"

  iso_file_id = proxmox_virtual_environment_download_file.talos_nocloud_image.id

  cpu_cores = 2
  memory    = 4096 # Control plane needs more memory
  disk_size = 20
}

# Talos Worker 1
module "talos_worker_1" {
  source = "../modules/talos-vm"

  name        = "talos-work-1"
  description = "Talos Linux Worker Node 1"
  node_name   = "pve"

  iso_file_id = proxmox_virtual_environment_download_file.talos_nocloud_image.id

  cpu_cores = 2
  memory    = 2048
  disk_size = 20
}

# Talos Worker 2
module "talos_worker_2" {
  source = "../modules/talos-vm"

  name        = "talos-work-2"
  description = "Talos Linux Worker Node 2"
  node_name   = "pve"

  iso_file_id = proxmox_virtual_environment_download_file.talos_nocloud_image.id

  cpu_cores = 2
  memory    = 2048
  disk_size = 20
}
