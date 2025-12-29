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
