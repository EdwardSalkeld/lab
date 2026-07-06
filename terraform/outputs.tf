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

output "hello_vm_ssh_username" {
  value       = "root"
  description = "SSH username baked into the zero-touch hello VM via native cloud-init"
}

output "hello_vm_ipv4_address" {
  value       = split("/", var.hello_ipv4_address)[0]
  description = "Static IPv4 address assigned to the zero-touch hello VM"
}
