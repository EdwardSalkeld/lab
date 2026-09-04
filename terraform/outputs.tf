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

output "kite_vm_id" {
  value       = var.enable_kite_vm ? proxmox_virtual_environment_vm.kite[0].vm_id : null
  description = "The auto-assigned VM ID for kite when enabled"
}

output "kite_vm_name" {
  value       = var.enable_kite_vm ? proxmox_virtual_environment_vm.kite[0].name : null
  description = "The name of kite when enabled"
}
