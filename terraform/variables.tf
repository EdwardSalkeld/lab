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

variable "partridge_vm_name" {
  description = "Name of the first repo-managed NixOS VM"
  type        = string
  default     = "partridge"
}

variable "partridge_root_disk_size" {
  description = "Root disk size for partridge in GiB"
  type        = number
  default     = 24
}

variable "partridge_code_disk_size" {
  description = "Code disk size for partridge in GiB"
  type        = number
  default     = 5
}

variable "partridge_postgres_disk_size" {
  description = "Postgres disk size for partridge in GiB"
  type        = number
  default     = 5
}

variable "partridge_vaultwarden_disk_size" {
  description = "Vaultwarden disk size for partridge in GiB"
  type        = number
  default     = 2
}

variable "partridge_prometheus_disk_size" {
  description = "Prometheus disk size for partridge in GiB"
  type        = number
  default     = 10
}

variable "partridge_loki_disk_size" {
  description = "Loki disk size for partridge in GiB"
  type        = number
  default     = 10
}

variable "magpie_vm_name" {
  description = "Name of the disposable NixOS development VM"
  type        = string
  default     = "magpie"
}

variable "magpie_root_disk_size" {
  description = "Root disk size for magpie in GiB"
  type        = number
  default     = 12
}
