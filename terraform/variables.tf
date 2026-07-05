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

variable "billy_public_ssh_keys" {
  description = "Billy's SSH public keys for persistent remote admin access"
  type        = list(string)
  default = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7g5CoTIOcrTpzDqFylWrcMGJIqOQC2RrYcWQzhD4NTB8Uh5ZHhR0LMfRhFXivIs3TY+bAe4ov7FODCOimL6irSoj6Pd/2La3o3hXGz2u/l1/7sLWxtG3H7k2QCOHacVzZUznJpn4rAGtfq2w8cmF/RNO1kc/ZncaIlh2TZ8f3D5cAEKUV2f7YN40d9MSnXNgg6YRgL91wfWDO7DMuWUi5UTqcH/3NBcJXsrTEQ7TT10ISabIVoLNROoAiORZY83iy1fYSGN3u3t72qcVdRIW1vZ7JbgaJ1ue4z2r1LkCKz4bGw3U76joloAv/V6rYR3o4+69atJaPhGapqiu8EkDF0eGjbfEzBi1sLehrzNH21Kv0TbNfwvUecCrvqZqNAhxPiedx1ws5BBcYDjAKpP3YU0hdmjoFDlBX4oFR7NhJ4lLWhAxgqCmzNvJAdFG0pya7hhsivc57vUibkdnRjNIJN+U3zwyT8xmRSiuaH8G1J1dDKjuMwlK0T2B4AsAwoJM= billy-lab@chatting"
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
  default     = 24
}

variable "hello_vm_name" {
  description = "Name of the zero-touch hello-world bootstrap VM"
  type        = string
  default     = "wren"
}

variable "hello_root_disk_size" {
  description = "Root disk size for the hello bootstrap VM in GiB"
  type        = number
  default     = 12
}

variable "hello_memory_mb" {
  description = "Memory for the hello bootstrap VM in MiB"
  type        = number
  default     = 2048
}
