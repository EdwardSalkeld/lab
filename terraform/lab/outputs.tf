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

output "talos_image_factory_schematic_id" {
  value       = talos_image_factory_schematic.qemu_guest_agent.id
  description = "Talos Image Factory schematic ID generated for qemu-guest-agent."
}

output "talos_image_factory_schematic_yaml" {
  value       = yamlencode(local.talos_qemu_schematic)
  description = "Rendered schematic YAML used to generate the Talos image factory schematic."
}
