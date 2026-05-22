output "nixos_vm_id" {
  value       = proxmox_virtual_environment_vm.nixos_01.vm_id
  description = "The auto-assigned VM ID for the first NixOS VM"
}

output "nixos_vm_name" {
  value       = proxmox_virtual_environment_vm.nixos_01.name
  description = "The name of the first NixOS VM"
}
