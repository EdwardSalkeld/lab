output "debian_12_container_id" {
  value       = module.debian_12_container.container_id
  description = "The auto-assigned VM ID for the Debian 12 container"
}

output "debian_12_container_password" {
  value       = module.debian_12_container.container_password
  sensitive   = true
  description = "Root password for the Debian 12 container"
}

output "debian_13_container_id" {
  value       = module.debian_13_container.container_id
  description = "The auto-assigned VM ID for the Debian 13 container"
}

output "debian_13_container_password" {
  value       = module.debian_13_container.container_password
  sensitive   = true
  description = "Root password for the Debian 13 container"
}

# Talos VMs
output "talos_control_plane_id" {
  value       = module.talos_control_plane.vm_id
  description = "VM ID for the Talos control plane"
}

output "talos_control_plane_ip" {
  value       = module.talos_control_plane.ipv4_addresses
  description = "IPv4 addresses for the Talos control plane"
}

output "talos_worker_1_id" {
  value       = module.talos_worker_1.vm_id
  description = "VM ID for Talos worker 1"
}

output "talos_worker_1_ip" {
  value       = module.talos_worker_1.ipv4_addresses
  description = "IPv4 addresses for Talos worker 1"
}

output "talos_worker_2_id" {
  value       = module.talos_worker_2.vm_id
  description = "VM ID for Talos worker 2"
}

output "talos_worker_2_ip" {
  value       = module.talos_worker_2.ipv4_addresses
  description = "IPv4 addresses for Talos worker 2"
}
