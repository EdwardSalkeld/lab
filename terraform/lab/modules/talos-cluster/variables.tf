variable "talos_cluster_name" {
  description = "Name of the Talos Linux cluster"
  type        = string
  default     = "talos-cluster"
}

variable "talos_ips" {
  type = list(string)
  default = [
    "10.4.1.40", # Control Plane
    "10.4.1.41", # Worker 1
    "10.4.1.42"  # Worker 2
  ]
}
locals {
  default_gateway = "10.4.1.1"
}
variable "proxmox_node_name" {
  type = string
}
variable "iso_file_id" {
  type = string
}
