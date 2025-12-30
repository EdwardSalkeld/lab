variable "name" {
  description = "Name of the Talos VM"
  type        = string
}

variable "description" {
  description = "Description of the Talos VM"
  type        = string
  default     = "Talos Linux VM"
}

variable "node_name" {
  description = "Proxmox node name"
  type        = string
}

variable "iso_file_id" {
  description = "File ID of the Talos ISO image"
  type        = string
}

variable "cpu_cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2
}

variable "memory" {
  description = "Memory in MB"
  type        = number
  default     = 2048
}

variable "disk_size" {
  description = "Disk size in GB"
  type        = number
  default     = 20
}

variable "datastore_id" {
  description = "Datastore for disks"
  type        = string
  default     = "local-lvm"
}

variable "network_bridge" {
  description = "Network bridge"
  type        = string
  default     = "vmbr0"
}

variable "on_boot" {
  description = "Start VM on boot"
  type        = bool
  default     = true
}

