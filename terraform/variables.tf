variable "PROXMOXTOKEN" {
  description = "API token for Proxmox Virtual Environment"
  type        = string
}
variable "PROXMOXENDPOINT" {
  description = "Endpoint for managing proxmox"
  type        = string
}

variable "public_ssh_keys" {
  description = "Edward's SSH public keys for NixOS access after manual install"
  type        = list(string)
  default = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGW8YuC9dt9wq2LptMHCfrg8n5l0nGUAd227vWCbqKUD edward@m1",
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzhdCoWE/CiY3laW9R/I5UEhQs7krz8ur8OOg7su5MJ edward@m2"
  ]
}

variable "proxmox_node_name" {
  description = "Proxmox node that will run the first NixOS VM"
  type        = string
  default     = "sol"
}

variable "proxmox_iso_datastore_id" {
  description = "Proxmox datastore for ISO images"
  type        = string
  default     = "local"
}

variable "proxmox_vm_datastore_id" {
  description = "Proxmox datastore for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "proxmox_network_bridge" {
  description = "Proxmox bridge for VM networking"
  type        = string
  default     = "vmbr0"
}

variable "nixos_vm_name" {
  description = "Name of the first NixOS VM"
  type        = string
  default     = "nixos-01"
}

variable "nixos_vm_disk_size" {
  description = "Root disk size for the first NixOS VM in GiB"
  type        = number
  default     = 32
}
