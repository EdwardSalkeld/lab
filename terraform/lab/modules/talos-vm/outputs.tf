output "vm_id" {
  description = "The ID of the VM"
  value       = proxmox_virtual_environment_vm.talos.vm_id
}

output "name" {
  description = "The name of the VM"
  value       = proxmox_virtual_environment_vm.talos.name
}

output "ipv4_addresses" {
  description = "The IPv4 addresses of the VM"
  value       = proxmox_virtual_environment_vm.talos.ipv4_addresses
}

output "mac_addresses" {
  description = "The MAC addresses of the VM"
  value       = proxmox_virtual_environment_vm.talos.mac_addresses
}
