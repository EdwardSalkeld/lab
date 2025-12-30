variable "talos_cluster_name" {
  description = "Name of the Talos Linux cluster"
  type        = string
  default     = "talos-cluster"
}

variable "proxmox_node_name" {
  type = string
}
variable "iso_file_id" {
  type = string
}
