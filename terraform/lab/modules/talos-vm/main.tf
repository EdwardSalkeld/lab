terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~>0.87"
    }
  }
}
resource "proxmox_virtual_environment_vm" "talos" {
  name        = var.name
  description = var.description
  node_name   = var.node_name

  # Use OVMF (UEFI) - Talos works better with UEFI
  bios = "ovmf"

  agent {
    enabled = true
  }

  cpu {
    cores = var.cpu_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.memory
  }

  network_device {
    bridge = var.network_bridge
  }

  # EFI disk required for OVMF
  efi_disk {
    datastore_id = var.datastore_id
  }

  # Boot from Talos ISO
  cdrom {
    file_id   = var.iso_file_id
    interface = "ide3"
  }

  # Disk for Talos to install to
  disk {
    datastore_id = var.datastore_id
    interface    = "virtio0"
    size         = var.disk_size
  }

  operating_system {
    type = "l26" # Linux 2.6+ kernel
  }

  on_boot = var.on_boot

  initialization {
    ip_config {
      ipv4 {
        address = "${var.ipv4_addr}/24"
        gateway = var.default_gateway
      }
      ipv6 {
        address = "dhcp"
      }
    }
  }
}
