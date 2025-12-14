terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.87.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.7.2"
    }
  }
}
provider "random" {
}

provider "proxmox" {
  endpoint  = var.PROXMOXENDPOINT
  api_token = var.PROXMOXTOKEN

  # Use random VM IDs to avoid conflicts (recommended)
  random_vm_ids = true

  # SSH configuration for disk operations (importing images, etc.)
  ssh {
    agent    = true
    username = "root"
  }

  # because self-signed TLS certificate is in use
  insecure = true

}
