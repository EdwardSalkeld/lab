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

variable "ARGOCD_REPO_URL" {
  description = "Git repo URL Argo CD should sync from (SSH or HTTPS)"
  type        = string
  default     = "git@github.com:EdwardSalkeld/lab.git"
}

variable "ARGOCD_REPO_REVISION" {
  description = "Git revision Argo CD should track"
  type        = string
  default     = "main"
}

variable "ARGOCD_REPO_PATH" {
  description = "Repo path Argo CD should sync"
  type        = string
  default     = "terraform/lab/gitops/stack"
}

variable "ARGOCD_REPO_SSH_PRIVATE_KEY" {
  description = "SSH private key for Argo CD repo access (leave empty to skip)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "ARGOCD_REPO_USERNAME" {
  description = "Username for HTTPS repo access (leave empty to skip)"
  type        = string
  default     = ""
}

variable "ARGOCD_REPO_PASSWORD" {
  description = "Password/token for HTTPS repo access (leave empty to skip)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "ARGOCD_APP_ENABLED" {
  description = "Whether to create the Argo CD Application (enable after Argo CD CRDs exist)"
  type        = bool
  default     = false
}
