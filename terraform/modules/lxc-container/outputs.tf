output "container_id" {
  description = "The ID of the created container"
  value       = proxmox_virtual_environment_container.this.vm_id
}

output "container_password" {
  description = "The generated root password for the container"
  value       = random_password.container_password.result
  sensitive   = true
}

output "hostname" {
  description = "The hostname of the container"
  value       = var.hostname
}
