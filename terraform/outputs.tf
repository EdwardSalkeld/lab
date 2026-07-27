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

output "chatting_vm_id" {
  value       = proxmox_virtual_environment_vm.chatting.vm_id
  description = "The auto-assigned VM ID for chatting"
}

output "chatting_vm_name" {
  value       = proxmox_virtual_environment_vm.chatting.name
  description = "The name of chatting"
}
