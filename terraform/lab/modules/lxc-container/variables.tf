variable "description" {
  description = "Description for the container"
  type        = string
  default     = "Managed by Terraform"
}

variable "node_name" {
  description = "Proxmox node name"
  type        = string
}

variable "vm_id" {
  description = "VM ID for the container (omit for auto-assignment)"
  type        = number
  default     = null
}

variable "timeout_create" {
  description = "Timeout for container creation in seconds"
  type        = number
  default     = 600
}

variable "timeout_update" {
  description = "Timeout for container updates in seconds"
  type        = number
  default     = 600
}

variable "timeout_delete" {
  description = "Timeout for container deletion in seconds"
  type        = number
  default     = 300
}

variable "unprivileged" {
  description = "Whether to create an unprivileged container"
  type        = bool
  default     = true
}

variable "features_nesting" {
  description = "Enable nesting feature"
  type        = bool
  default     = true
}

variable "hostname" {
  description = "Hostname for the container"
  type        = string
}

variable "ipv4_address" {
  description = "IPv4 address configuration (e.g., 'dhcp' or '192.168.1.10/24')"
  type        = string
  default     = "dhcp"
}

variable "ssh_keys" {
  description = "List of SSH public keys for root user"
  type        = list(string)
}

variable "root_password" {
  description = "Root user password"
  type        = string
  sensitive   = true
}

variable "network_interface_name" {
  description = "Network interface name"
  type        = string
  default     = "veth0"
}

variable "disk_datastore_id" {
  description = "Datastore ID for the root disk"
  type        = string
  default     = "local-lvm"
}

variable "disk_size" {
  description = "Root disk size in GB"
  type        = number
  default     = 4
}

variable "template_file_id" {
  description = "Template file ID for the container OS"
  type        = string
}

variable "os_type" {
  description = "Operating system type"
  type        = string
  default     = "debian"
}

variable "mount_points" {
  description = "Additional mount points for the container"
  type = list(object({
    volume = string
    size   = optional(string)
    path   = string
  }))
  default = []
}

variable "startup_order" {
  description = "Startup order"
  type        = string
  default     = "3"
}

variable "startup_up_delay" {
  description = "Startup up delay in seconds"
  type        = string
  default     = "60"
}

variable "startup_down_delay" {
  description = "Startup down delay in seconds"
  type        = string
  default     = "60"
}
