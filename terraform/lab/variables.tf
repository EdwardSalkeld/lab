variable "PROXMOXTOKEN" {
  description = "API token for Proxmox Virtual Environment"
  type        = string
}
variable "PROXMOXENDPOINT" {
  description = "Endpoint for managing proxmox"
  type        = string
}

variable "public_ssh_keys" {
  description = "Edward's SSH public key for container access"
  type        = list(string)
  default = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGW8YuC9dt9wq2LptMHCfrg8n5l0nGUAd227vWCbqKUD edward@m1",
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzhdCoWE/CiY3laW9R/I5UEhQs7krz8ur8OOg7su5MJ edward@m2"
  ]
}

variable "talos_version" {
  description = "Version of Talos Linux to deploy"
  type        = string
  default     = "v1.11.0"
}
variable "talos_cluster_name" {
  description = "Name of the Talos Linux cluster"
  type        = string
  default     = "talos-cluster"
}
