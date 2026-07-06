output "partridge_vm_id" {
  value       = proxmox_virtual_environment_vm.partridge.vm_id
  description = "The auto-assigned VM ID for partridge"
}

output "partridge_vm_name" {
  value       = proxmox_virtual_environment_vm.partridge.name
  description = "The name of partridge"
}

output "magpie_vm_id" {
  value       = proxmox_virtual_environment_vm.magpie.vm_id
  description = "The auto-assigned VM ID for magpie"
}

output "magpie_vm_name" {
  value       = proxmox_virtual_environment_vm.magpie.name
  description = "The name of magpie"
}

output "hello_vm_id" {
  value       = proxmox_virtual_environment_vm.hello.vm_id
  description = "The auto-assigned VM ID for the zero-touch hello VM"
}

output "hello_vm_name" {
  value       = proxmox_virtual_environment_vm.hello.name
  description = "The name of the zero-touch hello VM"
}

output "hello_vm_ipv4_addresses" {
  value       = proxmox_virtual_environment_vm.hello.ipv4_addresses
  description = "IPv4 addresses reported by the hello VM guest agent"
}
