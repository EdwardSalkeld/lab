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

output "vm" {
  description = "The Proxmox VM resource"
  value       = proxmox_virtual_environment_vm.talos
}
locals {
  all_ips          = compact(flatten(proxmox_virtual_environment_vm.talos.ipv4_addresses))
  non_loopback_ips = [for ip in local.all_ips : ip if startswith(ip, "10.4")]
  first_real_ip    = element(local.non_loopback_ips, 0)

}
output "ip" {
  value = local.first_real_ip
}
