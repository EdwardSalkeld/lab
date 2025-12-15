terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~>0.87"

    }
    random = {
      source = "hashicorp/random"
    }
  }
}
